import struct, zlib

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

w,h,ch,px=load_png(r"d:/evg-workplace/evg-base/front_clean.png")
cols=64; rows=48
chars=" .:-=+*#%@"
lines=[]
for ry in range(rows):
    row=""
    for rx in range(cols):
        x0=rx*w//cols; x1=(rx+1)*w//cols
        y0=ry*h//rows; y1=(ry+1)*h//rows
        s=0;n=0
        for y in range(y0,y1,max(1,(y1-y0)//3)):
            for x in range(x0,x1,max(1,(x1-x0)//3)):
                i=(y*w+x)*ch
                r=px[i]; g=px[i+1] if ch>=2 else r; b=px[i+2] if ch>=3 else r
                s += (r*299+g*587+b*114)//1000; n+=1
        lum = s//max(1,n)
        row += chars[min(9, lum*10//256)]
    lines.append(row)
with open(r"d:/evg-workplace/evg-base/ascii_view.txt","w",encoding="utf-8") as f:
    f.write("\n".join(lines))
    f.write("\n\nLegend: ' '=dark  '@'=bright")
