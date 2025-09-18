#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D texture;
uniform vec2 u_mouse;
uniform vec2 u_prevMouse;
uniform float u_brushSize;
uniform float u_isErasing;
uniform vec3 u_paintColor;
uniform float u_isRainbow;
uniform float u_time;
uniform float u_isImageMode;
uniform float u_imageSize;
uniform sampler2D u_stampImage;

varying vec4 vertTexCoord;

float distToSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

vec3 getRainbowColor(vec2 pos) {
    float phase = u_time + (pos.x + pos.y) * 0.01;
    vec3 color;
    color.r = sin(phase) * 0.5 + 0.5;
    color.g = sin(phase + 2.094) * 0.5 + 0.5;
    color.b = sin(phase + 4.189) * 0.5 + 0.5;
    return color;
}

void main() {
    vec2 uv = vertTexCoord.st;
    vec2 fragCoord = uv * vec2(576.0, 256.0);  // Canvas dimensions
    
    // Get existing color
    vec4 existingColor = texture2D(texture, uv);
    
    // Default to existing color
    vec4 outputColor = existingColor;
    
    // Check if mouse is active
    if (u_mouse.x >= 0.0) {
        if (u_isImageMode > 0.5) {
            // Image stamping mode
            float halfSize = u_imageSize * 0.5;
            vec2 imageCenter = u_mouse;
            
            // Check if within image stamp area
            if (abs(fragCoord.x - imageCenter.x) < halfSize && 
                abs(fragCoord.y - imageCenter.y) < halfSize) {
                
                // Calculate UV coordinates for the stamp image
                vec2 stampUV = (fragCoord - imageCenter + vec2(halfSize)) / u_imageSize;
                
                if (stampUV.x >= 0.0 && stampUV.x <= 1.0 && 
                    stampUV.y >= 0.0 && stampUV.y <= 1.0) {
                    vec4 stampColor = texture2D(u_stampImage, stampUV);
                    
                    // Apply stamp with alpha blending
                    if (stampColor.a > 0.1) {
                        outputColor = mix(existingColor, stampColor, stampColor.a);
                    }
                }
            }
        } else {
            // Regular brush mode
            float dist;
            
            // Calculate distance to brush stroke
            if (u_prevMouse.x >= 0.0) {
                // Distance to line segment between previous and current mouse
                dist = distToSegment(fragCoord, u_prevMouse, u_mouse);
            } else {
                // Distance to current mouse position only
                dist = distance(fragCoord, u_mouse);
            }
            
            // Apply brush if within radius
            if (dist < u_brushSize * 0.5) {
                if (u_isErasing > 0.5) {
                    // Erasing - blend towards white
                    outputColor = vec4(1.0, 1.0, 1.0, 1.0);
                } else {
                    // Painting
                    vec3 paintColor;
                    if (u_isRainbow > 0.5) {
                        paintColor = getRainbowColor(fragCoord);
                    } else {
                        paintColor = u_paintColor;
                    }
                    
                    // Apply paint color
                    outputColor = vec4(paintColor, 1.0);
                }
            }
        }
    }
    
    gl_FragColor = outputColor;
}