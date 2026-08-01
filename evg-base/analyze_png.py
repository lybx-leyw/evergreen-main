import sys, struct, zlib, collections

def load_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8
    width = height = bitd = color = None
    idat = b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if typ == b'IHDR':
            width, height, bitd, color = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0:1,2:3,3:1,4:2,6:4}[color]
    stride = width*ch
    out = bytearray()
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]; p+=1
        line = bytearray(raw[p:p+stride]); p+=stride
        for i in range(stride):
            a = line[i-ch] if i>=ch else 0
            b = prev[i]
            c = prev[i-ch] if i>=ch else 0
            if f==1: line[i]=(line[i]+a)&255
            elif f==2: line[i]=(line[i]+b)&255
            elif f==3: line[i]=(line[i]+((a+b)>>1))&255
            elif f==4:
                pp=a+b-c; pa=abs(pp-a); pb=abs(pp-b); pc=abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i]=(line[i]+pr)&255
        out+=line; prev=line
    return width, height, ch, out

path = r"d:/evg-workplace/evg-base/front_clean.png"
w,h,ch,px = load_png(path)
print("size=%dx%d channels=%d" % (w,h,ch))
# sample grid
import random
random.seed(0)
samples=[]
step=max(1,w//40)
for y in range(0,h,max(1,h//60)):
    for x in range(0,w,step):
        i=(y*w+x)*ch
        samples.append((px[i],px[i+1] if ch>=2 else px[i],px[i+2] if ch>=3 else px[i]))
colors=collections.Counter(samples)
print("distinct_sampled_colors=%d / %d" % (len(colors), len(samples)))
# variance
import statistics
rs=[c[0] for c in samples]; gs=[c[1] for c in samples]; bs=[c[2] for c in samples]
print("R std=%.1f G std=%.1f B std=%.1f" % (statistics.pstdev(rs),statistics.pstdev(gs),statistics.pstdev(bs)))
print("top5 colors (r,g,b):count =", colors.most_common(5))
# mean
print("mean RGB = (%.1f,%.1f,%.1f)" % (sum(rs)/len(rs), sum(gs)/len(gs), sum(bs)/len(bs)))
