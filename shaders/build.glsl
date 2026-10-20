#version 320 es
precision highp float;
// @duration 0.45
// Omarchy / HyprWindowShade close-snapshot interface. Premultiplied alpha.
// Brick rows come away from the top down, each brick dropping and fading. Played in reverse it builds from the bottom up.
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;
uniform float seed;
uniform vec4 window_rect;
uniform vec2 surface_size;
#define CELLS 18.0
float hash21(vec2 p) {
    return fract(sin(dot(p + seed, vec2(127.1, 311.7))) * 43758.5453);
}
vec2 hash22(vec2 p) { return vec2(hash21(p), hash21(p + 17.3)); }
mat2 rotate2(float a) {
    float s=sin(a), c=cos(a);
    return mat2(c, -s, s, c);
}
bool inside(vec2 p) { return all(greaterThanEqual(p, vec2(0.0))) && all(lessThan(p, vec2(1.0))); }
vec4 sourceAt(vec2 p) {
    if (!inside(p)) return vec4(0.0);
    return texture(tex, window_rect.xy + p * window_rect.zw);
}
void main() {
    float p=clamp(progress,0.0,1.0);
    if(p>=1.0) { fragColor=vec4(0.0); return; }
    if(p<=0.0) { fragColor=texture(tex,v_texcoord); return; }
    vec2 uv=(v_texcoord-window_rect.xy)/max(window_rect.zw,vec2(0.00001));
    // The border and shadow lie outside the window's rect; fade them quickly instead of leaving fragments.
    if(!inside(uv)) { fragColor=texture(tex,v_texcoord)*(1.0-smoothstep(0.0,0.3,p)); return; }
    vec2 pixels=max(surface_size*window_rect.zw,vec2(1.0));
    vec2 bricks=vec2(max(3.0,floor(CELLS*0.5)), max(3.0,floor(CELLS*0.5*pixels.y/pixels.x*2.0+0.5)));
    vec2 x=uv*bricks;
    float row=floor(x.y);
    vec4 result=vec4(0.0);
    // Bricks fall straight down, so only the rows above this pixel can cover it.
    for(int j=-4;j<=0;j++) {
        float r=row+float(j);
        if(r<0.0 || r>=bricks.y) continue;
        // Alternate rows are offset by half a brick, like a wall.
        float stagger=mod(r,2.0)*0.5;
        float col=floor(x.x-stagger+0.5+0.0);
        for(int i=-1;i<=1;i++) {
            vec2 id=vec2(col+float(i),r);
            vec2 h=hash22(id);
            float delay=0.55*(r/bricks.y)+0.15*h.x;
            float t=clamp((p-delay)/0.30,0.0,1.0);
            vec2 at=vec2(id.x+0.5+stagger,r+0.5+3.0*t*t);
            vec2 local=(x-at)/(1.0-0.35*t);
            if(any(greaterThanEqual(abs(local),vec2(0.5)))) continue;
            vec4 part=sourceAt(vec2(id.x+0.5+stagger+local.x,r+0.5+local.y)/bricks)*(1.0-smoothstep(0.35,1.0,t));
            result=part+result*(1.0-part.a);
        }
    }
    fragColor=result;
}
