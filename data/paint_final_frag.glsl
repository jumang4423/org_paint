#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
uniform vec2 u_mouse;
uniform vec2 u_prevMouse;
uniform float u_brushSize;
uniform float u_isErasing;
uniform vec3 u_paintColor;

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
    vec2 pixelPos = vec2(uv.x * 576.0, (1.0 - uv.y) * 256.0);
    
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
    
    // Create hard-edged brush mask (no antialiasing)
    float brushRadius = u_brushSize * 0.5;
    float mask = dist <= brushRadius ? 1.0 : 0.0;  // Hard cutoff, no smoothstep
    
    // Paint or erase
    vec4 paintColor = u_isErasing > 0.5 ? vec4(1.0, 1.0, 1.0, 1.0) : vec4(u_paintColor, 1.0);
    
    // Apply brush
    gl_FragColor = mix(prevColor, paintColor, mask);
}