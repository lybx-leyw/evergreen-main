"""离线单元测试 —— 验证 scraper.py 的 RSA 加密与解析/组装逻辑。

登录与网络环节需真实浙大凭据+校园网，无法离线自动化；本测试只覆盖
「纯逻辑」：RSA modpow 正确性、各 parse_* 函数、以及 scrape() 组装出的
数据形状是否严格匹配 classroom-modle 的 bindings 语义键路径。

运行： python test_scraper.py
"""
import json
import scraper


_passed = 0
_failed = 0


def check(name, cond):
    global _passed, _failed
    if cond:
        _passed += 1
        print(f'  [PASS] {name}')
    else:
        _failed += 1
        print(f'  [FAIL] {name}')


# ---- 1. RSA modpow ----
def test_rsa():
    # 已知小参数：mod=3233 (61*53), exp=17, "A"=0x41=65 → 65^17 mod 3233
    enc = scraper.rsa_encrypt('A', 'ca1', '11')  # mod=3233, exp=17
    check('rsa 返回 128 位十六进制', len(enc) == 128)
    check('rsa 值与 pow 一致', int(enc, 16) == pow(0x41, 0x11, 0xca1))


# ---- 2. parse_courses ----
def test_parse_courses():
    raw = {'params': {'result': {'data': [
        {'Id': 123, 'Title': '高等数学', 'Teacher': '张三，李四'},
        {'Id': '456', 'Title': '线性代数', 'Teacher': '王五'},
    ]}}}
    out = scraper.parse_courses(raw)
    check('课程数=2', len(out) == 2)
    check('course.id 来自 Id(int)', out[0]['id'] == 123)
    check('course.title 来自 Title', out[0]['title'] == '高等数学')
    check('course.teachers 拆分为 List', out[0]['teachers'] == ['张三', '李四'])
    check('单教师也是 List', out[1]['teachers'] == ['王五'])
    check('parse_courses 空输入不报错', scraper.parse_courses(None) == [])


# ---- 3. parse_videos ----
def test_parse_videos():
    raw = {'result': {'data': [
        {'sub_id': 7, 'title': '第一讲', 'status': '6',
         'content': json.dumps({'playback': {'url': 'http://x/v.m3u8'}})},
        {'sub_id': 8, 'title': '未完成', 'status': '3', 'content': ''},
        {'sub_id': 9, 'title': '第二讲', 'status': '6',
         'content': json.dumps({'video_url': 'http://x/v2.mp4'})},
    ]}}
    out = scraper.parse_videos(raw)
    check('仅保留 status==6', len(out) == 2)
    check('video.id 来自 sub_id', out[0]['subId'] == 7)
    check('video.title 来自 title', out[0]['title'] == '第一讲')
    check('videoUrl 取 playback.url', out[0]['videoUrl'] == 'http://x/v.m3u8')
    check('videoUrl 回退 video_url', out[1]['videoUrl'] == 'http://x/v2.mp4')
    check('video.slides 初始为空 List', out[0]['slides'] == [])
    check('video.subtitles 初始为空 List', out[0]['subtitles'] == [])


# ---- 4. parse_slides ----
def test_parse_slides():
    pages = [{
        'list': [
            {'content': json.dumps({'pptimgurl': 'p1.png', 'text': '第一页'})},
            {'content': json.dumps({'pptimgurl': 'p2.png', 'text': '第二页'})},
            {'content': json.dumps({'pptimgurl': 'p1.png', 'text': '重复'})},
        ]
    }]
    out = scraper.parse_slides(pages)
    check('PPT 去重后=2', len(out) == 2)
    check('slide.page 递增', [s['page'] for s in out] == [1, 2])
    check('slide.imageUrl 来自 pptimgurl', out[0]['imageUrl'] == 'p1.png')
    check('slide.text 来自 text', out[1]['text'] == '第二页')


# ---- 5. parse_subtitles ----
def test_parse_subtitles():
    raw = {'list': [{'all_content': [
        {'BeginSec': 0, 'Text': '大家好'},
        {'BeginSec': '3.5', 'Text': '今天讲极限'},
        {'BeginSec': 10, 'Text': '   '},  # 空文本应被过滤
    ]}]}
    out = scraper.parse_subtitles(raw)
    check('字幕过滤空文本后=2', len(out) == 2)
    check('subtitle.startMs = BeginSec*1000', out[0]['startMs'] == 0)
    check('subtitle.startMs 支持小数秒', out[1]['startMs'] == 3500)
    check('subtitle.endMs=0', out[0]['endMs'] == 0)
    check('subtitle.text 来自 Text', out[1]['text'] == '今天讲极限')


# ---- 6. scrape() 组装形状匹配 bindings ----
class _FakeSession:
    """按 URL 返回预置原始响应，模拟真实 API。"""

    def get_json(self, url):
        if 'account-profile/course' in url:
            return {'params': {'result': {'data': [
                {'Id': 1, 'Title': '数学', 'Teacher': '张三'}]}}}
        if 'catalogue' in url:
            return {'result': {'data': [
                {'sub_id': 100, 'title': '第一讲', 'status': '6',
                 'content': json.dumps({'playback': {'url': 'http://x/v.m3u8'}})}]}}
        if 'search-ppt' in url:
            return {'list': [
                {'content': json.dumps({'pptimgurl': 'p1.png', 'text': 't1'})}]}
        if 'search-trans-result' in url:
            return {'list': [{'all_content': [
                {'BeginSec': 1, 'Text': '字幕1'}]}]}
        return None


def test_scrape_shape():
    result = scraper.scrape(_FakeSession(), max_videos=3, time_budget=999)
    # bindings: courses → courses
    check('顶层含 courses', isinstance(result.get('courses'), list))
    course = result['courses'][0]
    # course.* 键路径
    check('course.id', course['id'] == 1)
    check('course.title', course['title'] == '数学')
    check('course.teachers', course['teachers'] == ['张三'])
    check('course.videos 是 List', isinstance(course['videos'], list))
    video = course['videos'][0]
    # video.* 键路径
    check('video.id(subId)', video['subId'] == 100)
    check('video.title', video['title'] == '第一讲')
    check('video.videoUrl', video['videoUrl'] == 'http://x/v.m3u8')
    check('video.slides 是 List', isinstance(video['slides'], list))
    check('video.subtitles 是 List', isinstance(video['subtitles'], list))
    # slide.* / subtitle.* 键路径
    slide = video['slides'][0]
    check('slide.page', slide['page'] == 1)
    check('slide.imageUrl', slide['imageUrl'] == 'p1.png')
    check('slide.text', slide['text'] == 't1')
    sub = video['subtitles'][0]
    check('subtitle.startMs', sub['startMs'] == 1000)
    check('subtitle.endMs', sub['endMs'] == 0)
    check('subtitle.text', sub['text'] == '字幕1')
    # 整体可 JSON 序列化（register_data_source 要求 stdout 为合法 JSON）
    check('结果可 JSON 序列化', bool(json.dumps(result, ensure_ascii=False)))


def test_scrape_budget():
    # 超时预算下，PPT/字幕不抓，但视频列表仍在（slides/subtitles 空）
    result = scraper.scrape(_FakeSession(), max_videos=3, time_budget=-1)
    v = result['courses'][0]['videos'][0]
    check('超预算时 slides 为空', v['slides'] == [])
    check('超预算时 subtitles 为空', v['subtitles'] == [])
    check('超预算时视频列表仍在', v['subId'] == 100)


if __name__ == '__main__':
    print('== RSA ==')
    test_rsa()
    print('== parse_courses ==')
    test_parse_courses()
    print('== parse_videos ==')
    test_parse_videos()
    print('== parse_slides ==')
    test_parse_slides()
    print('== parse_subtitles ==')
    test_parse_subtitles()
    print('== scrape shape (bindings) ==')
    test_scrape_shape()
    print('== scrape budget ==')
    test_scrape_budget()
    print(f'\n结果: {_passed} 通过 / {_failed} 失败')
    raise SystemExit(1 if _failed else 0)
