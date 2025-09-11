#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
uniform vec2 u_mouse;
uniform vec2 u_prevMouse;
uniform float u_brushSize;
uniform float u_isErasing;

varying vec4 vertTexCoord;

float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void main() {
    // Get texture coordinates 
    vec2 uv = vertTexCoord.st;
    
    // Get pixel position - Y座標を反転
    vec2 pixelPos = vec2(uv.x * 576.0, (1.0 - uv.y) * 1024.0);
    
    // Sample previous frame
    vec4 prevColor = texture2D(texture, uv);
    
    // Calculate distance to brush stroke
    float dist;
    if (u_prevMouse.x < 0.0) {
        // Single point
        dist = distance(pixelPos, u_mouse);
    } else {
        // Line segment for smooth strokes
        dist = sdSegment(pixelPos, u_prevMouse, u_mouse);
    }
    
    // Create smooth brush mask
    float brushRadius = u_brushSize * 0.5;
    float mask = 1.0 - smoothstep(brushRadius - 2.0, brushRadius + 2.0, dist);
    
    // Paint or erase
    vec4 paintColor = mix(vec4(0.0, 0.0, 0.0, 1.0), vec4(1.0, 1.0, 1.0, 1.0), u_isErasing);
    
    // Apply brush
    gl_FragColor = mix(prevColor, paintColor, mask);
}