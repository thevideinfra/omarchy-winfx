#!/usr/bin/env python3
"""Compile shipped ES shaders, check endpoints and render a synthetic-window demo.
Requires Mesa EGL (surfaceless ES 3.2) and Pillow; no live compositor is used.
"""
import argparse
import subprocess
import ctypes as C
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

I, U, F, P = C.c_int, C.c_uint, C.c_float, C.c_void_p
E = C.CDLL('libEGL.so.1')
def egl(name, result, *args):
    fn = getattr(E, name); fn.restype = result; fn.argtypes = args; return fn
getproc = egl('eglGetProcAddress', P, C.c_char_p)
def gl(name, result, *args):
    address = getproc(name.encode())
    if not address: raise RuntimeError('Unavailable GL function: '+name)
    return C.CFUNCTYPE(result, *args)(address)

def context(width, height):
    platform = C.CFUNCTYPE(P, U, P, C.POINTER(I))(getproc(b'eglGetPlatformDisplayEXT'))
    display = platform(0x31DD, None, None)
    major, minor = I(), I()
    assert egl('eglInitialize', U, P, C.POINTER(I), C.POINTER(I))(display, C.byref(major), C.byref(minor)), 'EGL init failed'
    assert egl('eglBindAPI', U, U)(0x30A0)
    attrs=(I*15)(0x3033,1,0x3040,0x40,0x3024,8,0x3023,8,0x3022,8,0x3021,8,0x3025,0,0x3038)
    cfg=P(); count=I()
    assert egl('eglChooseConfig', U,P,C.POINTER(I),C.POINTER(P),I,C.POINTER(I))(display,attrs,C.byref(cfg),1,C.byref(count)) and count.value
    surface=egl('eglCreatePbufferSurface',P,P,P,C.POINTER(I))(display,cfg,(I*5)(0x3057,width,0x3056,height,0x3038))
    ctx=egl('eglCreateContext',P,P,P,P,C.POINTER(I))(display,cfg,None,(I*3)(0x3098,3,0x3038))
    assert ctx and egl('eglMakeCurrent',U,P,P,P,P)(display,surface,surface,ctx), 'ES3 context unavailable'
    print(gl('glGetString',C.c_char_p,U)(0x1F02).decode())

def shader(kind, source):
    handle=gl('glCreateShader',U,U)(kind)
    raw=C.c_char_p(source.encode())
    gl('glShaderSource',None,U,I,C.POINTER(C.c_char_p),C.POINTER(I))(handle,1,C.byref(raw),None)
    gl('glCompileShader',None,U)(handle)
    ok=I(); gl('glGetShaderiv',None,U,U,C.POINTER(I))(handle,0x8B81,C.byref(ok))
    if not ok.value:
        buf=C.create_string_buffer(16384)
        gl('glGetShaderInfoLog',None,U,I,C.POINTER(I),P)(handle,16384,None,buf)
        raise AssertionError(buf.value.decode())
    return handle

def program(fragment):
    vertex='''#version 320 es
    precision highp float;
    out vec2 v_texcoord;
    void main(){ vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));
    v_texcoord=p; gl_Position=vec4(p*2.0-1.0,0.0,1.0); }'''
    prog=gl('glCreateProgram',U)()
    for handle in [shader(0x8B31,vertex),shader(0x8B30,fragment)]:
        gl('glAttachShader',None,U,U)(prog,handle)
    gl('glLinkProgram',None,U)(prog)
    ok=I(); gl('glGetProgramiv',None,U,U,C.POINTER(I))(prog,0x8B82,C.byref(ok))
    assert ok.value, 'Shader link failed'
    return prog


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,default=Path('/tmp/omarchy-winfx-frames'))
    args=parser.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    w,h=360,240; context(w,h)
    window=Image.new('RGBA',(w,h)); draw=ImageDraw.Draw(window)
    box=(72,48,287,191)
    draw.rounded_rectangle(box,6,fill='#1b2030',outline='#7aa2f7',width=2)
    draw.rectangle((74,68,285,70),fill='#424b66')
    draw.text((84,53),'WinFX',fill='#c0caf5')
    for i in range(5):
        draw.rectangle((88,87+i*17,245-i*12,93+i*17),fill=['#7aa2f7','#9ece6a','#bb9af7'][i%3])
    tex=U(); gl('glGenTextures',None,I,C.POINTER(U))(1,C.byref(tex))
    gl('glBindTexture',None,U,U)(0x0DE1,tex.value)
    for name, val in [(0x2801,0x2600),(0x2800,0x2600),(0x2802,0x812F),(0x2803,0x812F)]:
        gl('glTexParameteri',None,U,U,I)(0x0DE1,name,val)
    data=window.tobytes(); buf=C.create_string_buffer(data)
    gl('glTexImage2D',None,U,I,I,I,I,I,U,U,P)(0x0DE1,0,0x1908,w,h,0,0x1908,0x1401,buf)
    gl('glViewport',None,I,I,I,I)(0,0,w,h)
    gl('glDisable',None,U)(0x0BE2)
    vao=U(); gl('glGenVertexArrays',None,I,C.POINTER(U))(1,C.byref(vao)); gl('glBindVertexArray',None,U)(vao)
    read=gl('glReadPixels',None,I,I,I,I,U,U,P)
    frames={}
    for path in sorted((Path(__file__).parents[1]/'shaders').glob('*.glsl')):
        prog=program(path.read_text()); gl('glUseProgram',None,U)(prog)
        loc=lambda name: gl('glGetUniformLocation',I,U,C.c_char_p)(prog,name.encode())
        gl('glUniform1i',None,I,I)(loc('tex'),0)
        gl('glUniform1f',None,I,F)(loc('seed'),0.37)
        gl('glUniform2f',None,I,F,F)(loc('surface_size'),w,h)
        gl('glUniform4f',None,I,F,F,F,F)(loc('window_rect'),.2,.2,.6,.6)
        images=[]
        for step in range(31):
            gl('glUniform1f',None,I,F)(loc('progress'),step/30)
            gl('glDrawArrays',None,U,I,I)(0x0004,0,3)
            pixels=(C.c_ubyte*(w*h*4))(); read(0,0,w,h,0x1908,0x1401,pixels)
            img=Image.frombytes('RGBA',(w,h),bytes(pixels))
            if step==0: assert img.tobytes()==data, path.name+' changed starting frame'
            if step==30: assert img.getchannel('A').getextrema()[1]==0, path.name+' not transparent at end'
            assert all(r<=a and g<=a and b<=a for r,g,b,a in zip(*[iter(img.tobytes())]*4)), path.name+' invalid premultiplication'
            # GPU outputs premultiplied RGBA; compose over opaque background manually.
            bg=(15,17,26)
            rgb=Image.new('RGB',(w,h)); rgb.putdata([(min(255,r+round(bg[0]*(1-a/255))),min(255,g+round(bg[1]*(1-a/255))),min(255,b+round(bg[2]*(1-a/255)))) for r,g,b,a in zip(*[iter(img.tobytes())]*4)])
            images.append(rgb)
        images[15].save(args.output/(path.stem+'.png'))
        frames[path.stem]=images
        print(path.name+': compiled, rendered 31 frames, endpoints and premultiplied alpha passed')
    font=None
    for candidate in subprocess.run(['fc-match','-f','%{file}','sans'],capture_output=True,text=True).stdout.split('\n')[:1] + ['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
        try: font=ImageFont.truetype(candidate,16); break
        except OSError: pass
    font=font or ImageFont.load_default()
    names=['crumble','shatter','dissolve','pixelate','explode','build','blinds','glitch']
    columns=4; rows=(len(names)+columns-1)//columns
    combined=[]
    for step in [0]*10+list(range(31))+[30]*8:
        panel=Image.new('RGB',(w*columns,45+rows*(h+42)),'#0f111a'); d=ImageDraw.Draw(panel)
        d.text((16,12),'WinFX · closing, rendered from the shipped shaders on a synthetic window (opening plays them in reverse)',font=font,fill='#c0caf5')
        for i,name in enumerate(names):
            x=(i%columns)*w; y=45+(i//columns)*(h+42)
            d.text((x+16,y),name.capitalize(),font=font,fill='#7aa2f7')
            panel.paste(frames[name][step],(x,y+22))
        combined.append(panel.resize((panel.width*3//4,panel.height*3//4),Image.LANCZOS))
    combined[25].save(args.output/'effects.png')
    combined[0].save(args.output/'effects.gif',save_all=True,append_images=combined[1:],duration=30,loop=0,optimize=True)
    print('Preview saved to',args.output/'effects.gif')

if __name__=='__main__': main()
