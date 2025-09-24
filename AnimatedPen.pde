// AnimatedPen class - manages particle animations placed on canvas
class AnimatedPen {
  ArrayList<AnimationInstance> animations;
  int currentAnimationType = 0; // 0 = cloud/smoke
  String[] animationTypeNames = {"CLOUD"};
  float globalCloudDensity = 0.5; // Global cloud density for new animations (controlled by CC4)
  
  AnimatedPen() {
    animations = new ArrayList<AnimationInstance>();
  }
  
  // Add new animation at position with size
  void addAnimation(float x, float y, float scrollY, float size) {
    AnimationInstance anim = null;
    
    switch(currentAnimationType) {
      case 0: // Cloud/smoke animation
        anim = new CloudAnimation(x, y + scrollY, size, globalCloudDensity);
        break;
      // Add more animation types here in the future
    }
    
    if (anim != null) {
      animations.add(anim);
    }
  }
  
  // Set cloud density for new animations (doesn't affect existing ones)
  void setCloudDensity(float density) {
    globalCloudDensity = constrain(density, 0, 1.0);
    // DO NOT update existing animations - they keep their creation-time density
  }
  
  // Update all animations
  void update(float deltaSeconds, float timeScale) {
    // Update animations and remove dead ones
    for (int i = animations.size() - 1; i >= 0; i--) {
      AnimationInstance anim = animations.get(i);
      anim.update(deltaSeconds, timeScale);
      if (anim.isDead()) {
        animations.remove(i);
      }
    }
  }
  
  // Draw all animations
  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    for (AnimationInstance anim : animations) {
      anim.draw(canvas, scrollY, isZoomed, zoomScale, zoomOffsetX, zoomOffsetY);
    }
  }
  
  // Remove animations that intersect with eraser rectangle
  void eraseAtRect(float x, float y, float width, float height, float scrollY) {
    float globalY = y + scrollY;
    for (int i = animations.size() - 1; i >= 0; i--) {
      AnimationInstance anim = animations.get(i);
      if (anim.intersectsRect(x, globalY, width, height)) {
        animations.remove(i);
      }
    }
  }
  
  // Remove animations that intersect with eraser circle (legacy)
  void eraseAt(float x, float y, float radius, float scrollY) {
    float globalY = y + scrollY;
    for (int i = animations.size() - 1; i >= 0; i--) {
      AnimationInstance anim = animations.get(i);
      if (anim.intersects(x, globalY, radius)) {
        animations.remove(i);
      }
    }
  }
  
  // Get current animation type name
  String getCurrentTypeName() {
    return animationTypeNames[currentAnimationType];
  }
  
  // Cycle to next animation type
  void nextAnimationType() {
    currentAnimationType = (currentAnimationType + 1) % animationTypeNames.length;
  }
  
  // Save animations to file
  void saveToFile(String filename) {
    ArrayList<String> data = new ArrayList<String>();
    
    // Save header
    data.add("ANIMATED_PEN_V1");
    data.add("globalCloudDensity:" + globalCloudDensity);
    data.add("animationCount:" + animations.size());
    
    // Save each animation
    for (AnimationInstance anim : animations) {
      String animData = "ANIMATION:";
      
      // Save type
      if (anim instanceof CloudAnimation) {
        CloudAnimation cloud = (CloudAnimation)anim;
        animData += "CLOUD,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += cloud.cloudDensity;
      }
      // Add more animation types here in the future
      
      data.add(animData);
    }
    
    saveStrings(filename, data.toArray(new String[0]));
  }
  
  // Load animations from file
  void loadFromFile(String filename) {
    try {
      String[] data = loadStrings(filename);
      if (data == null || data.length == 0) return;
      
      // Clear existing animations
      animations.clear();
      
      // Check header
      if (!data[0].equals("ANIMATED_PEN_V1")) return;
      
      // Parse data
      for (int i = 1; i < data.length; i++) {
        String line = data[i];
        
        if (line.startsWith("globalCloudDensity:")) {
          globalCloudDensity = Float.parseFloat(line.split(":")[1]);
        } else if (line.startsWith("ANIMATION:")) {
          // Parse animation
          String[] parts = line.substring(10).split(",");
          if (parts.length >= 1) {
            String type = parts[0];
            
            if (type.equals("CLOUD") && parts.length >= 5) {
              float x = Float.parseFloat(parts[1]);
              float y = Float.parseFloat(parts[2]);
              float size = Float.parseFloat(parts[3]);
              float density = Float.parseFloat(parts[4]);
              
              CloudAnimation cloud = new CloudAnimation(x, y, size, density);
              animations.add(cloud);
            }
            // Add more animation types here in the future
          }
        }
      }
    } catch (Exception e) {
      println("Error loading animated pen: " + e.getMessage());
    }
  }
}

// Base class for all animation instances
abstract class AnimationInstance {
  float originX, originY; // Origin point (global coordinates)
  float baseSize; // Base size for the animation
  
  AnimationInstance(float x, float y, float size) {
    this.originX = x;
    this.originY = y;
    this.baseSize = size;
  }
  
  abstract void update(float deltaSeconds, float timeScale);
  abstract void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY);
  abstract boolean intersects(float x, float y, float radius);
  abstract boolean intersectsRect(float x, float y, float width, float height);
  
  boolean isDead() {
    return false; // Animations never die, they loop forever
  }
}

// Cloud/Smoke animation - particles floating upward
class CloudAnimation extends AnimationInstance {
  ArrayList<CloudParticle> particles;
  int particleSpawnInterval = 200; // Spawn new particle every 200ms
  int lastSpawn = 0;
  int baseMaxParticles = 10; // Base maximum number of particles
  float cloudDensity; // 0 = minimal clouds, 1.0 = maximum clouds (locked at creation time)
  
  CloudAnimation(float x, float y, float size) {
    super(x, y, size);
    particles = new ArrayList<CloudParticle>();
    cloudDensity = 0.5; // Default density
    // Start with a few particles based on density
    int initialParticles = max(1, (int)(3 * cloudDensity));
    for (int i = 0; i < initialParticles; i++) {
      particles.add(new CloudParticle(originX, originY, baseSize));
    }
  }
  
  CloudAnimation(float x, float y, float size, float density) {
    super(x, y, size);
    particles = new ArrayList<CloudParticle>();
    cloudDensity = constrain(density, 0, 1.0);
    // Start with a few particles based on density
    int initialParticles = max(1, (int)(3 * cloudDensity));
    for (int i = 0; i < initialParticles; i++) {
      particles.add(new CloudParticle(originX, originY, baseSize));
    }
  }
  
  void update(float deltaSeconds, float timeScale) {
    // Calculate dynamic max particles based on density
    int maxParticles = max(2, (int)(baseMaxParticles * cloudDensity * 2)); // 0-20 particles based on density

    // Adjust spawn interval based on density (faster spawning with higher density)
    int dynamicSpawnInterval = (int)(particleSpawnInterval / max(0.2, cloudDensity));
    
    // Continuously spawn new particles
    if (millis() - lastSpawn > dynamicSpawnInterval) {
      // Always maintain particles based on density
      if (particles.size() < maxParticles) {
        particles.add(new CloudParticle(originX, originY, baseSize));
      }
      lastSpawn = millis();
    }
    
    // Update particles and recycle dead ones
    for (int i = particles.size() - 1; i >= 0; i--) {
      CloudParticle p = particles.get(i);
      p.update(deltaSeconds, timeScale);
      if (p.isDead()) {
        // Replace dead particle with new one to keep animation going
        particles.set(i, new CloudParticle(originX, originY, baseSize));
      }
    }
  }
  
  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();
    
    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }
    
    for (CloudParticle p : particles) {
      float drawY = p.y - scrollY;
      
      // Only draw if visible
      if (drawY > -50 && drawY < canvas.height + 50) {
        // Draw cloud particle as horizontal ellipse with black border
        float alpha = p.alpha * (1.0 - p.age / p.maxAge);
        
        // Gray border with no interior fill
        canvas.stroke(160, 160, 160, alpha * 255);
        canvas.strokeWeight(1);
        canvas.noFill();
        
        // Horizontal ellipse (wider than tall)
        canvas.ellipse(p.x, drawY, p.size * 1.5, p.size * 0.7);
      }
    }
    
    if (isZoomed) {
      canvas.popMatrix();
    }
    
    canvas.popStyle();
  }
  
  boolean intersects(float x, float y, float radius) {
    // Check if eraser intersects with origin or any particles
    float dist = dist(x, y, originX, originY);
    if (dist < radius + 20) return true;
    
    for (CloudParticle p : particles) {
      dist = dist(x, y, p.x, p.y);
      if (dist < radius + p.size/2) return true;
    }
    
    return false;
  }
  
  boolean intersectsRect(float x, float y, float width, float height) {
    // Check if rectangle intersects with origin
    float halfW = width / 2;
    float halfH = height / 2;
    
    // Check if origin is inside rectangle
    if (originX >= x - halfW && originX <= x + halfW &&
        originY >= y - halfH && originY <= y + halfH) {
      return true;
    }
    
    // Check if any particle is inside rectangle
    for (CloudParticle p : particles) {
      if (p.x >= x - halfW && p.x <= x + halfW &&
          p.y >= y - halfH && p.y <= y + halfH) {
        return true;
      }
    }
    
    return false;
  }
}

// Individual cloud particle
class CloudParticle {
  float x, y;
  float vx, vy;
  float size;
  float age = 0;
  float maxAge = 3000; // 3 seconds per particle lifecycle
  float alpha;
  float baseSize;
  
  CloudParticle(float originX, float originY, float animSize) {
    this.baseSize = animSize;
    
    // Start at origin with some random offset scaled by size
    this.x = originX + random(-baseSize * 0.3, baseSize * 0.3);
    this.y = originY + random(-baseSize * 0.2, baseSize * 0.2);
    
    // Random upward velocity with slight horizontal drift (scaled by size)
    this.vx = random(-0.2, 0.2) * (baseSize / 20);
    this.vy = random(-1.2, -0.4) * (baseSize / 20); // Negative for upward movement
    
    // Random size based on animation size
    this.size = random(baseSize * 0.5, baseSize);
    
    // Starting alpha
    this.alpha = random(0.4, 0.7);
  }
  
  void update(float deltaSeconds, float timeScale) {
    float deltaMillis = deltaSeconds * 1000.0f;
    age += deltaMillis;

    x += vx * timeScale;
    y += vy * timeScale;

    vx += random(-0.01, 0.01) * (baseSize / 20) * timeScale;
    vx *= pow(0.99f, timeScale);

    size += 0.05 * (baseSize / 20) * timeScale;

    alpha *= pow(0.997f, timeScale);
  }
  
  boolean isDead() {
    // Particles die when they fade out or get too old
    return age > maxAge || alpha < 0.05 || y < -200; // Also die if too far up
  }
}
