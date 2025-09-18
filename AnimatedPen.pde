// AnimatedPen class - manages particle animations placed on canvas
class AnimatedPen {
  ArrayList<AnimationInstance> animations;
  int currentAnimationType = 0; // 0 = cloud/smoke
  String[] animationTypeNames = {"CLOUD"};
  
  AnimatedPen() {
    animations = new ArrayList<AnimationInstance>();
  }
  
  // Add new animation at position with size
  void addAnimation(float x, float y, float scrollY, float size) {
    AnimationInstance anim = null;
    
    switch(currentAnimationType) {
      case 0: // Cloud/smoke animation
        anim = new CloudAnimation(x, y + scrollY, size);
        break;
      // Add more animation types here in the future
    }
    
    if (anim != null) {
      animations.add(anim);
    }
  }
  
  // Update all animations
  void update() {
    // Update animations and remove dead ones
    for (int i = animations.size() - 1; i >= 0; i--) {
      AnimationInstance anim = animations.get(i);
      anim.update();
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
  
  abstract void update();
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
  int maxParticles = 10; // Maximum number of particles at once
  
  CloudAnimation(float x, float y, float size) {
    super(x, y, size);
    particles = new ArrayList<CloudParticle>();
    // Start with a few particles
    for (int i = 0; i < 3; i++) {
      particles.add(new CloudParticle(originX, originY, baseSize));
    }
  }
  
  void update() {
    // Continuously spawn new particles
    if (millis() - lastSpawn > particleSpawnInterval) {
      // Always maintain some particles
      if (particles.size() < maxParticles) {
        particles.add(new CloudParticle(originX, originY, baseSize));
      }
      lastSpawn = millis();
    }
    
    // Update particles and recycle dead ones
    for (int i = particles.size() - 1; i >= 0; i--) {
      CloudParticle p = particles.get(i);
      p.update();
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
        
        // Black border
        canvas.stroke(0, 0, 0, alpha * 255); // Black border with same alpha
        canvas.strokeWeight(1);
        
        // Lighter gray fill (200 instead of 150)
        canvas.fill(200, 200, 200, alpha * 150); // Lighter gray, more transparent
        
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
  
  void update() {
    age += 16; // ~60fps
    
    // Move particle
    x += vx;
    y += vy;
    
    // Slight horizontal drift over time
    vx += random(-0.01, 0.01) * (baseSize / 20);
    vx *= 0.99; // Damping
    
    // Grow slightly over time
    size += 0.05 * (baseSize / 20);
    
    // Fade out over time (but not completely)
    alpha *= 0.997;
  }
  
  boolean isDead() {
    // Particles die when they fade out or get too old
    return age > maxAge || alpha < 0.05 || y < -200; // Also die if too far up
  }
}