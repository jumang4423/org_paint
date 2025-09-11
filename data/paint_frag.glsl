#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D texture;
uniform sampler2D u_canvas;
uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform vec2 u_prevMouse;
uniform float u_brushSize;
uniform float u_isErasing;

varying vec4 vertColor;
varying vec4 vertTexCoord;

float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

void main() {
    vec2 uv = vertTexCoord.st;
    vec2 pixelPos = uv * u_resolution;
    
    // Get the previous color from the texture
    vec4 prevColor = texture2D(texture, uv);
    
    // Calculate distance to brush stroke
    float dist;
    if (u_prevMouse.x < 0.0) {
        // Single point (mouse just pressed)
        dist = distance(pixelPos, u_mouse);
    } else {
        // Line segment between previous and current mouse position
        dist = sdSegment(pixelPos, u_prevMouse, u_mouse);
    }
    
    // Create brush mask with smooth edges
    float brushRadius = u_brushSize * 0.5;
    float mask = 1.0 - smoothstep(brushRadius - 2.0, brushRadius + 2.0, dist);
    
    // Apply paint or erase
    vec4 paintColor = vec4(0.0, 0.0, 0.0, 1.0); // Black paint
    vec4 eraseColor = vec4(1.0, 1.0, 1.0, 1.0); // White (erase)
    
    vec4 targetColor = mix(paintColor, eraseColor, u_isErasing);
    
    // Mix with previous color based on mask
    gl_FragColor = mix(prevColor, targetColor, mask);
}