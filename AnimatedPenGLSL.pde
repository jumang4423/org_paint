// GPU-based animated pen using GLSL shaders
class AnimatedPenGLSL {
  ArrayList<AnimationData> animations;
  int currentAnimationType = 0;
  String[] animationTypeNames = {"CLOUD"};
  boolean needsUpdate = false;
  
  class AnimationData {
    float x, y;  // Position in global coordinates
    float size;
    float startTime;
    
    AnimationData(float x, float y, float size) {
      this.x = x;
      this.y = y;
      this.size = size;
      this.startTime = millis() / 1000.0;  // Convert to seconds
    }
  }
  
  AnimatedPenGLSL() {
    animations = new ArrayList<AnimationData>();
  }
  
  // Add new animation
  void addAnimation(float x, float y, float scrollY, float size) {
    AnimationData anim = new AnimationData(x, y + scrollY, size);
    animations.add(anim);
    needsUpdate = true;
    
    // Limit to 100 animations
    if (animations.size() > 100) {
      animations.remove(0);
    }
  }
  
  // Update animation data texture for GPU
  void updateDataTexture(PGraphics dataTexture) {
    if (!needsUpdate) return;
    
    dataTexture.beginDraw();
    dataTexture.loadPixels();
    
    // Clear texture
    for (int i = 0; i < dataTexture.pixels.length; i++) {
      dataTexture.pixels[i] = color(0, 0, 0, 0);
    }
    
    // Write animation data to texture
    for (int i = 0; i < animations.size() && i < 100; i++) {
      AnimationData anim = animations.get(i);
      
      // Normalize values to 0-1 range for texture storage
      float normalizedX = anim.x / CANVAS_WIDTH;
      float normalizedY = anim.y / (CHUNK_HEIGHT * 20);  // Assume max 20 chunks
      float normalizedSize = anim.size / 100.0;  // Max size 100
      float normalizedTime = anim.startTime / 100.0;  // Scale time
      
      // Store in texture as RGBA (x, y, size, time)
      int pixelIndex = i * 4;  // Each animation uses 4 pixels (one row)
      if (pixelIndex < dataTexture.pixels.length) {
        // Pack data into color channels
        dataTexture.pixels[pixelIndex] = color(
          normalizedX * 255,
          normalizedY * 255, 
          normalizedSize * 255,
          normalizedTime * 255
        );
      }
    }
    
    dataTexture.updatePixels();
    dataTexture.endDraw();
    
    needsUpdate = false;
  }
  
  // Render animations with GLSL shader
  void renderWithShader(PGraphics canvas, PShader shader, float scrollY) {
    if (shader == null || animations.isEmpty()) return;
    
    float currentTime = millis() / 1000.0;
    
    // Prepare arrays for shader (limit to 20 animations)
    int count = min(animations.size(), 20);
    float[] positions = new float[count * 2];
    float[] sizes = new float[count];
    float[] startTimes = new float[count];
    
    for (int i = 0; i < count; i++) {
      AnimationData anim = animations.get(i);
      positions[i * 2] = anim.x;
      positions[i * 2 + 1] = anim.y;
      sizes[i] = anim.size;
      startTimes[i] = anim.startTime;
    }
    
    // Set shader uniforms
    shader.set("u_time", currentTime);
    shader.set("u_scrollY", scrollY);
    shader.set("u_animCount", count);
    
    // Set arrays
    shader.set("u_animPositions", positions, 2);
    shader.set("u_animSizes", sizes, 1);
    shader.set("u_animStartTimes", startTimes, 1);
    
    // Apply shader
    canvas.filter(shader);
  }
  
  // Check if animation should be erased
  void eraseAtRect(float x, float y, float width, float height, float scrollY) {
    float globalY = y + scrollY;
    for (int i = animations.size() - 1; i >= 0; i--) {
      AnimationData anim = animations.get(i);
      
      // Check if animation origin is within erase rectangle
      if (anim.x >= x - width/2 && anim.x <= x + width/2 &&
          anim.y >= globalY - height/2 && anim.y <= globalY + height/2) {
        animations.remove(i);
        needsUpdate = true;
      }
    }
  }
  
  // Draw deletion markers when in eraser mode (CPU side for UI)
  void drawEraserMarkers(PGraphics canvas, float scrollY, float mouseX, float mouseY) {
    for (AnimationData anim : animations) {
      float dist = dist(mouseX, mouseY + scrollY, anim.x, anim.y);
      boolean isNear = dist < 50;
      
      if (isNear) {
        canvas.pushStyle();
        
        float rectX = anim.x;
        float rectY = anim.y - scrollY;
        float rectSize = 20;
        
        // Orange highlight
        canvas.stroke(255, 165, 0, 200);
        canvas.strokeWeight(2);
        canvas.noFill();
        canvas.rect(rectX - rectSize/2, rectY - rectSize/2, rectSize, rectSize);
        
        // X mark
        canvas.line(rectX - 5, rectY - 5, rectX + 5, rectY + 5);
        canvas.line(rectX - 5, rectY + 5, rectX + 5, rectY - 5);
        
        canvas.popStyle();
      }
    }
  }
  
  String getCurrentTypeName() {
    return animationTypeNames[currentAnimationType];
  }
  
  void nextAnimationType() {
    currentAnimationType = (currentAnimationType + 1) % animationTypeNames.length;
  }
}