import struct, zlib, statistics

def load_png(path):
    data = open(path, 'rb').read()
    pos = 8; width=height=color=None; idat=b''
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; chunk = data[pos+8:pos+8+ln]
        if typ==b'IHDR': width,height,_,color = struct.unpack('>IIBB', chunk[:10])
        elif typ==b'IDAT': idat+=chunk
        elif typ==b'IEND': break
        pos += 12+ln
    raw = zlib.decompress(idat)
    ch = {0:1,2:3,3:1,4:2,6:4}[color]; stride=width*ch
    out=bytearray(); prev=bytearray(stride); p=0
    for y in range(height):
        f=raw[p]; p+=1; line=bytearray(raw[p:p+stride]); p+=stride
        for i in range(stride):
            a=line[i-ch] if i>=ch else 0; b=prev[i]; c=prev[i-ch] if i>=ch else 0
            if f==1: line[i]=(line[i]+a)&255
            elif f==2: line[i]=(line[i]+b)&255
            elif f==3: line[i]=(line[i]+((a+b)>>1))&255
            elif f==4:
                pp=a+b-c; pa=abs(pp-a); pb=abs(pp-b); pc=abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[i]=(line[i]+pr)&255
        out+=line; prev=line
    return width,height,ch,out

w,h,ch,px=load_png(r"d:/evg-workplace/evg-base/front_home.png")
def lum(x,y):
    i=(y*w+x)*ch
    r=px[i]; g=px[i+1] if ch>=2 else r; b=px[i+2] if ch>=3 else r
    return (r*299+g*587+b*114)//1000

# content density map: 16x16 blocks, '+' if high variance/text, '.' if flat
bw, bh = 20, 40
lines=[]
for by in range(bh):
    row=""
    for bx in range(bw):
        xs=range(bx*w//bw, (bx+1)*w//bw, 2)
        ys=range(by*h//bh, (by+1)*h//bh, 2)
        vals=[lum(x,y) for y in ys for x in xs]
        std = statistics.pstdev(vals) if len(vals)>1 else 0
        row += '#' if std>35 else (':' if std>15 else '.')
    lines.append(row)
with open(r"d:/evg-workplace/evg-base/density_map.txt","w",encoding="utf-8") as f:
    f.write("\n".join(lines))
    f.write("\n\n'#'=text/edge  ':'=some contrast  '.'=flat")
