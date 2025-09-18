#ifdef GL_ES
precision mediump float;
precision mediump int;
#endif

uniform sampler2D texture;
uniform float u_time;
uniform float u_scrollY;

// Animation uniforms - up to 20 animations
uniform vec2 u_animPositions[20];
uniform float u_animSizes[20];
uniform float u_animStartTimes[20];
uniform int u_animCount;

varying vec4 vertTexCoord;

// Cloud particle animation
vec4 drawCloud(vec2 fragCoord, vec2 animPos, float animSize, float animStartTime) {
    float timeSinceStart = u_time - animStartTime;
    
    // Multiple particles per animation
    vec4 result = vec4(0.0);
    
    for(int i = 0; i < 5; i++) {
        float particlePhase = float(i) * 0.3 + timeSinceStart * 0.5;
        
        // Particle position - drift up and sideways
        vec2 particlePos = animPos;
        particlePos.x += sin(particlePhase + float(i)) * animSize * 0.3;
        particlePos.y -= mod(particlePhase * 20.0, animSize * 2.0); // Float upward (negative Y is up)
        
        // Particle size - grows over time
        float particleSize = animSize * (0.5 + mod(particlePhase * 0.1, 0.5));
        
        // Horizontal ellipse (1.5x wider than tall)
        vec2 diff = fragCoord - particlePos;
        diff.x /= 1.5;
        diff.y *= 1.43; // 1/0.7 to make it flatter
        float dist = length(diff);
        
        if(dist < particleSize) {
            // Fade based on lifetime
            float age = mod(timeSinceStart + float(i) * 0.5, 3.0);
            float alpha = 1.0 - age / 3.0;
            
            // Black border
            if(dist > particleSize - 1.0) {
                result = mix(result, vec4(0.0, 0.0, 0.0, 1.0), alpha * 0.8);
            } else {
                // Light gray fill
                result = mix(result, vec4(0.78, 0.78, 0.78, 1.0), alpha * 0.4);
            }
        }
    }
    
    return result;
}

void main() {
    vec2 uv = vertTexCoord.st;
    vec2 fragCoord = uv * vec2(576.0, 324.0); // Canvas size
    
    // Flip Y for screen coordinates (Y increases downward)
    fragCoord.y = 324.0 - fragCoord.y;
    
    // Add scroll offset
    fragCoord.y += u_scrollY;
    
    // Get existing color
    vec4 existingColor = texture2D(texture, uv);
    vec4 outputColor = existingColor;
    
    // Process each animation
    for(int i = 0; i < 20; i++) {
        if(i >= u_animCount) break;
        
        vec2 animPos = u_animPositions[i];
        float animSize = u_animSizes[i];
        float animStartTime = u_animStartTimes[i];
        
        // Draw cloud animation
        vec4 cloudColor = drawCloud(fragCoord, animPos, animSize, animStartTime);
        
        // Blend with existing
        if(cloudColor.a > 0.01) {
            outputColor = mix(outputColor, cloudColor, cloudColor.a);
        }
    }
    
    gl_FragColor = outputColor;
}