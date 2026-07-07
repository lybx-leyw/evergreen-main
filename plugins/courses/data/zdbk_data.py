"""zdbk_data.exe — 课程数据拉取（CLI，一次性执行）。

用法:
  zdbk_data.exe --type=courses_list      → stdout JSON → exit
  zdbk_data.exe --type=courses_timetable → stdout JSON → exit
"""
import argparse
import json
import os
import re
import ssl
import sys
import urllib.request
import urllib.parse
import http.cookiejar

_PROJECT_ROOT = ""

# PyInstaller 打包后 SSL 证书可能不可用，创建不验证证书的 context（仅用于 ZJU 内网）
_SSL_CONTEXT = None
try:
	_SSL_CONTEXT = ssl.create_default_context()
except Exception:
	_SSL_CONTEXT = ssl._create_unverified_context()


def _urlopen(req, timeout=10):
	"""urlopen 包装器：回退到不验证 SSL 证书（兼容 PyInstaller 打包）。"""
	try:
		return urllib.request.urlopen(req, timeout=timeout, context=_SSL_CONTEXT)
	except Exception:
		# 如果默认 context 失败，用不验证的重试
		return urllib.request.urlopen(req, timeout=timeout,
		                               context=ssl._create_unverified_context())


def _get_config(key):
	p = os.path.join(_PROJECT_ROOT, ".config_port")
	if not os.path.isfile(p):
		return None
	try:
		with open(p) as f:
			port = f.read().strip()
		url = f"http://127.0.0.1:{port}/config/settings/{key}"
		req = urllib.request.Request(url)
		with urllib.request.urlopen(req, timeout=5) as resp:
			data = json.loads(resp.read().decode("utf-8"))
			return data.get("value") if isinstance(data, dict) else None
	except Exception:
		return None


def _rsa_encrypt(plaintext, modulus_hex, exponent_hex):
	n = int(modulus_hex, 16)
	e = int(exponent_hex, 16)
	m = int(plaintext.encode("utf-8").hex(), 16)
	if m >= n:
		raise ValueError("Message too large")
	h = hex(pow(m, e, n))[2:]
	return "0" + h if len(h) % 2 else h


def _cas_login():
	u = _get_config("ZJU_USERNAME")
	p = _get_config("ZJU_PASSWORD")
	if not u or not p:
		raise Exception("未设置学号/密码（请在设置中配置 ZJU_USERNAME 和 ZJU_PASSWORD）")

	cj = http.cookiejar.CookieJar()
	op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
	hd = {"User-Agent": "Mozilla/5.0"}

	# Step 1: execution token
	try:
		r1 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login", headers=hd)
		b1 = _urlopen(r1, timeout=15).read().decode("utf-8")
	except Exception as e:
		raise Exception(f"无法连接 CAS 登录页（请检查网络连接）: {e}")
	m = re.search(r'name="execution"\s+value="([^"]+)"', b1)
	if not m:
		raise Exception("CAS 登录页结构异常（execution token 未找到，可能页面已更新）")
	execution = m.group(1)

	# Step 2: RSA pubkey
	try:
		r2 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/v2/getPubKey", headers=hd)
		pk = json.loads(_urlopen(r2, timeout=10).read().decode("utf-8"))
	except Exception as e:
		raise Exception(f"获取 CAS 公钥失败: {e}")
	pwd_enc = _rsa_encrypt(p, pk["modulus"], pk["exponent"])

	# Step 3: login
	body = (f"username={urllib.parse.quote(u)}"
	        f"&password={urllib.parse.quote(pwd_enc)}"
	        f"&execution={urllib.parse.quote(execution)}"
	        f"&_eventId=submit&rememberMe=true")
	r4 = urllib.request.Request("https://zjuam.zju.edu.cn/cas/login",
	                            data=body.encode("utf-8"),
	                            headers={"Content-Type": "application/x-www-form-urlencoded", **hd})
	try:
		_urlopen(r4, timeout=15).read()
	except Exception as e:
		raise Exception(f"CAS 登录请求失败: {e}")

	for c in cj:
		if c.name == "iPlanetDirectoryPro":
			return c.value
	raise Exception("登录失败：学号或密码错误（未获取到 CAS 会话凭证）")


def _zdbk_session(iplanet):
	cj = http.cookiejar.CookieJar()
	op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj),
	                                 urllib.request.HTTPRedirectHandler())
	url = ("https://zjuam.zju.edu.cn/cas/login"
	       "?service=https%3A%2F%2Fzdbk.zju.edu.cn%2Fjwglxt%2Fxtgl%2Flogin_ssologin.html")
	r = urllib.request.Request(url, headers={"Cookie": f"iPlanetDirectoryPro={iplanet}",
	                                          "User-Agent": "Mozilla/5.0"})
	try:
		_urlopen(r, timeout=15).read()
	except Exception as e:
		raise Exception(f"ZDBK SSO 跳转失败: {e}")
	for c in cj:
		if c.name == "JSESSIONID":
			return cj, op
	raise Exception("ZDBK 登录失败（未获取到 JSESSIONID，可能是教务系统维护中）")


# ═════════════════════════════════════
# 数据拉取函数
# ═════════════════════════════════════

def fetch_courses_list():
	iplanet = _cas_login()
	req = urllib.request.Request("https://courses.zju.edu.cn/api/my-courses")
	req.add_header("Cookie", f"iPlanetDirectoryPro={iplanet}")
	req.add_header("User-Agent", "Mozilla/5.0")
	req.add_header("Content-Type", "application/json")
	try:
		data = json.loads(_urlopen(req, timeout=15).read().decode("utf-8"))
	except Exception as e:
		raise Exception(f"获取课程列表失败（网络或 API 异常）: {e}")
	courses = data.get("courses", data.get("data", []))
	return {"courses": [
		{"id": str(c.get("id", "")), "name": c.get("name", c.get("title", "")),
		 "teacherName": c.get("teacherName", ""), "courseTypeName": c.get("courseTypeName", ""),
		 "statusLabel": "进行中", "courseCode": c.get("courseCode", c.get("code", ""))}
		for c in courses
	], "total": len(courses)}


def fetch_timetable():
	import datetime
	iplanet = _cas_login()
	cj, op = _zdbk_session(iplanet)
	now = datetime.datetime.now()
	year = now.year if now.month >= 9 else now.year - 1
	headers = {
		"Referer": "https://zdbk.zju.edu.cn/jwglxt/xtgl/index_initMenu.html",
		"User-Agent": "Mozilla/5.0",
		"Accept": "application/json, text/javascript, */*; q=0.01",
		"X-Requested-With": "XMLHttpRequest",
	}
	body = urllib.parse.urlencode({"xnm": str(year), "xqm": "12"}).encode("utf-8")
	req = urllib.request.Request("https://zdbk.zju.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html",
	                             data=body, headers=headers)
	try:
		html = op.open(req, timeout=15).read().decode("utf-8")
	except Exception as e:
		raise Exception(f"获取课表失败（网络或 API 异常）: {e}")
	m = re.search(r'"kbList"\s*:\s*(\[.*?\])', html, re.DOTALL)
	if not m:
		raise Exception("课表数据解析失败（响应结构异常，可能教务系统已更新）")
	sessions = []
	for it in json.loads(m.group(1)):
		if not it.get("kcb"):
			continue
		kcb = it["kcb"]
		parts = kcb.split("<br>")
		nm = parts[0].strip() if parts else "?"
		t = parts[2].strip() if len(parts) >= 3 else ""
		loc = (parts[3].split("zwf")[0].strip()) if len(parts) >= 4 else ""
		sessions.append({
			"courseName": nm, "teacher": t, "location": loc,
			"dayOfWeek": int(it.get("xqj", 1)),
			"periods": list(range(int(it.get("djj", 1)), int(it.get("djj", 1)) + int(it.get("skcd", 1)))),
			"courseId": it.get("xkkh", ""),
		})
	return {"sessions": sessions}


HANDLERS = {"courses_list": fetch_courses_list, "courses_timetable": fetch_timetable}

if __name__ == "__main__":
	p = argparse.ArgumentParser()
	p.add_argument("--type", required=True)
	p.add_argument("--project-root", default=os.getcwd())
	args = p.parse_args()
	_PROJECT_ROOT = os.path.abspath(args.project_root)

	h = HANDLERS.get(args.type)
	if not h:
		print(json.dumps({"error": f"unknown type: {args.type}"}, ensure_ascii=False))
		sys.exit(1)

	try:
		result = h()
		print(json.dumps(result, ensure_ascii=False))
	except Exception as e:
		sys.stderr.write(f"[zdbk] {args.type}: {e}\n")
		print(json.dumps({"error": str(e)}, ensure_ascii=False))
		sys.exit(1)
