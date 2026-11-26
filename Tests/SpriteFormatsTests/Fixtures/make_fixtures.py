import zlib, struct, sys, os
out = sys.argv[1]
def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)

def filt(rowbytes, prev, f, bpp):
    o = bytearray()
    for i,x in enumerate(rowbytes):
        a = rowbytes[i-bpp] if i>=bpp else 0; b = prev[i]; c = prev[i-bpp] if i>=bpp else 0
        if f==0: p=0
        elif f==1: p=a
        elif f==2: p=b
        elif f==3: p=(a+b)//2
        else:
            pp=a+b-c; pa,pb,pc=abs(pp-a),abs(pp-b),abs(pp-c)
            p = a if pa<=pb and pa<=pc else (b if pb<=pc else c)
        o.append((x-p)&255)
    return bytes([f])+bytes(o)

def pack_samples(samples, depth):
    if depth==8: return bytes(samples)
    if depth==16: return b''.join(struct.pack('>H',s) for s in samples)
    bits=''.join(format(s,'0%db'%depth) for s in samples)
    bits+= '0'*((8-len(bits)%8)%8)
    return bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8))

def encode(name, w, h, depth, ct, sample_fn, plte=None, trns=None, interlace=False):
    channels={0:1,2:3,3:1,4:2,6:4}[ct]
    bpp=max(1,channels*depth//8)
    passes=[(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)] if interlace else [(0,0,1,1)]
    raw=b''; rowi=0
    for xs,ys,dx,dy in passes:
        pw=(w-xs+dx-1)//dx; ph=(h-ys+dy-1)//dy
        if pw<=0 or ph<=0: continue
        prev=bytes(len(pack_samples([0]*(pw*channels),depth)))
        for py in range(ph):
            y=ys+py*dy
            samples=[]
            for px in range(pw):
                samples+=sample_fn(xs+px*dx,y)
            rb=pack_samples(samples,depth)
            raw+=filt(rb,prev,rowi%5,bpp); prev=rb; rowi+=1
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,depth,ct,0,0,1 if interlace else 0))
    if plte: data+=chunk(b'PLTE',bytes(sum(plte,[])))
    if trns is not None: data+=chunk(b'tRNS',bytes(trns))
    # split IDAT across two chunks to test concatenation
    comp=zlib.compress(raw,9)
    half=len(comp)//2
    # IDAT chunks must be consecutive; the ancillary chunk goes before them.
    data+=chunk(b'tEXt',b'Comment\x00test')+chunk(b'IDAT',comp[:half])+chunk(b'IDAT',comp[half:])+chunk(b'IEND',b'')
    open(os.path.join(out,'PNG',name+'.png'),'wb').write(data)

def expect(name,w,h,fn):
    open(os.path.join(out,'PNG',name+'.rgba'),'wb').write(bytes(sum((fn(x,y) for y in range(h) for x in range(w)),[])))

W,H=19,13
rgba=lambda x,y:[(x*16+y*3)&255,(x*y*7)&255,(255-x*9)&255,(y*20+x)&255]
encode('rgba8',W,H,8,6,rgba); expect('rgba8',W,H,rgba)
encode('rgba8-interlaced',W,H,8,6,rgba,interlace=True); expect('rgba8-interlaced',W,H,rgba)
rgb16=lambda x,y:[x*3000,y*4000,(x+y)*1000]
encode('rgb16-trns',W,H,16,2,rgb16,trns=list(struct.pack('>HHH',3000,4000,2000)))
# 16-bit samples are reduced with libpng's rounding (png_set_scale_16).
scale16=lambda v:(v*255+32895)>>16
expect('rgb16-trns',W,H,lambda x,y:[scale16(x*3000),scale16(y*4000),scale16((x+y)*1000), 0 if (x,y)==(1,1) else 255])
g1=lambda x,y:[(x+y)%2]
encode('gray1',W,H,1,0,g1); expect('gray1',W,H,lambda x,y:[255*((x+y)%2)]*3+[255])
g4=lambda x,y:[(x*y)%16]
encode('gray4-trns',W,H,4,0,g4,trns=[0,5]); expect('gray4-trns',W,H,lambda x,y:[((x*y)%16)*17]*3+[0 if (x*y)%16==5 else 255])
pal=[[255,0,0],[0,255,0],[0,0,255],[255,255,255]]
p2=lambda x,y:[(x+2*y)%4]
encode('palette2-trns',W,H,2,3,p2,plte=pal,trns=[255,128]); expect('palette2-trns',W,H,lambda x,y: pal[(x+2*y)%4]+[[255,128,255,255][(x+2*y)%4]])
ga=lambda x,y:[(x*13)&255,(y*19)&255]
encode('graya8-interlaced',W,H,8,4,ga,interlace=True); expect('graya8-interlaced',W,H,lambda x,y:[(x*13)&255]*3+[(y*19)&255])
