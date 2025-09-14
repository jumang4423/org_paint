#ifdef GL_ES
precision mediump float;
#endif

uniform sampler2D texture;
uniform sampler2D u_stampImage;
uniform vec2 u_mouse;
uniform vec2 u_prevMouse;
uniform float u_brushSize;
uniform float u_isErasing;
uniform vec3 u_paintColor;
uniform float u_isRainbow;
uniform float u_time;
uniform float u_isImageMode;
uniform float u_imageSize;

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
    
    // Check if we're in image stamp mode
    if (u_isImageMode > 0.5) {
        // Image stamp mode - only stamp at mouse position, no line interpolation
        vec2 imageCenter = u_mouse;
        float halfSize = u_imageSize * 0.5;
        
        // Calculate UV coordinates for the stamp image
        vec2 stampUV = (pixelPos - (imageCenter - vec2(halfSize))) / u_imageSize;
        
        // Only process pixels that are within the texture's UV range [0,1]
        if (stampUV.x >= 0.0 && stampUV.x <= 1.0 && 
            stampUV.y >= 0.0 && stampUV.y <= 1.0) {
            // Sample the stamp image
            vec4 stampColor = texture2D(u_stampImage, stampUV);
            
            // Use the image's native alpha channel for transparency
            // Alpha determines visibility - no rectangular boundary
            gl_FragColor = mix(prevColor, stampColor, stampColor.a);
        } else {
            // Outside texture bounds
            gl_FragColor = prevColor;
        }
    } else {
        // Regular brush mode
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
        vec4 paintColor;
        if (u_isErasing > 0.5) {
            paintColor = vec4(1.0, 1.0, 1.0, 1.0);  // White for erasing
        } else if (u_isRainbow > 0.5) {
            // Rainbow color based on position and time
            float rainbow = (pixelPos.x + pixelPos.y + u_time * 500.0) * 0.02;
            vec3 rainbowColor = vec3(
                sin(rainbow) * 0.5 + 0.5,
                sin(rainbow + 2.094) * 0.5 + 0.5,  // 2π/3
                sin(rainbow + 4.189) * 0.5 + 0.5   // 4π/3
            );
            paintColor = vec4(rainbowColor, 1.0);
        } else {
            paintColor = vec4(u_paintColor, 1.0);
        }
        
        // Apply brush
        gl_FragColor = mix(prevColor, paintColor, mask);
    }
}