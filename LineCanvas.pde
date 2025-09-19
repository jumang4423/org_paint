// LineCanvas class - captures all drawing as line segments and animates them
class LineCanvas {
  // Line segment storage
  ArrayList<LineSegment> lines;
  ArrayList<LineSegment> activeLines; // Currently visible lines
  
  // Animation parameters
  float waveTime = 0;
  float waveSpeed = 0.05;  // Faster base speed
  float waveAmplitude = 5;   // Much smaller Y range (was 20)
  float waveFrequency = 0.08; // Higher frequency for faster oscillation
  float animationIntensity = 0.5; // 0 = stopped, 1.0 = full speed (controlled by MIDI CC4)
  
  // Viewport parameters  
  float viewportY = 0; // Current Y position in the infinite canvas
  float viewportSpeed = 1.0; // Scrolling speed
  
  // Line style
  color lineColor = color(0);
  float lineWeight = 2.0;
  
  // Maximum lines to keep in memory
  int maxLines = 10000;
  
  LineCanvas() {
    lines = new ArrayList<LineSegment>();
    activeLines = new ArrayList<LineSegment>();
  }
  
  // Start a new line stroke
  void startStroke(float x, float y) {
    // Create a new line starting at this point with current color, weight, and animation intensity
    LineSegment newLine = new LineSegment(x, y, lineColor, lineWeight, animationIntensity);
    lines.add(newLine);
    
    // Keep line count under control
    if (lines.size() > maxLines) {
      lines.remove(0);
    }
  }
  
  // Add point to current stroke
  void addPoint(float x, float y) {
    if (lines.isEmpty()) {
      startStroke(x, y);
      return;
    }
    
    // Add point to the last line segment
    LineSegment currentLine = lines.get(lines.size() - 1);
    currentLine.addPoint(x, y);
  }
  
  // End current stroke
  void endStroke() {
    // Stroke automatically ends when startStroke is called again
  }
  
  // Update animation
  void update() {
    waveTime += waveSpeed;  // Global time for reference
    
    // Update each line's animation based on its own intensity
    for (LineSegment line : lines) {
      line.updateAnimation(waveSpeed);
    }
    
    // Update active lines based on viewport
    activeLines.clear();
    for (LineSegment line : lines) {
      if (line.isVisible(viewportY, SCREEN_HEIGHT)) {
        activeLines.add(line);
      }
    }
  }
  
  // Draw all visible lines with Vib-Ribbon style animation
  void draw(PGraphics canvas) {
    canvas.pushStyle();
    canvas.strokeWeight(lineWeight);
    canvas.noFill();
    
    for (LineSegment line : activeLines) {
      // Use each line's stored animation intensity, not the global one
      line.drawAnimated(canvas, waveTime, waveAmplitude, waveFrequency, viewportY);
    }
    
    canvas.popStyle();
  }
  
  // Draw with zoom support
  void draw(PGraphics canvas, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();
    
    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }
    
    canvas.strokeWeight(lineWeight);
    canvas.noFill();
    
    for (LineSegment line : activeLines) {
      // Use each line's stored animation intensity, not the global one
      line.drawAnimated(canvas, waveTime, waveAmplitude, waveFrequency, viewportY);
    }
    
    if (isZoomed) {
      canvas.popMatrix();
    }
    
    canvas.popStyle();
  }
  
  // Clear all lines
  void clear() {
    lines.clear();
    activeLines.clear();
  }
  
  // Set line color
  void setColor(color c) {
    // Backwards-compatible: default to non-rainbow
    setColorAndRainbow(c, false);
  }

  // Set line color and whether it should animate as rainbow
  void setColorAndRainbow(color c, boolean isRainbow) {
    lineColor = c;
    // Apply to current line if exists
    if (!lines.isEmpty()) {
      LineSegment currentLine = lines.get(lines.size() - 1);
      currentLine.strokeColor = c;
      currentLine.isRainbow = isRainbow;
    }
  }
  
  // Set line weight
  void setWeight(float w) {
    lineWeight = w;
    // Apply to current line if exists
    if (!lines.isEmpty()) {
      LineSegment currentLine = lines.get(lines.size() - 1);
      currentLine.strokeWeight = w;
    }
  }
  
  // Set animation intensity (0-1)
  void setAnimationIntensity(float intensity) {
    animationIntensity = constrain(intensity, 0, 1.0);
  }
  
  // Scroll viewport
  void scrollTo(float y) {
    viewportY = y;
  }
  
  // Erase lines at position with radius
  void eraseAt(float x, float y, float radius) {
    // Remove any line segments that intersect with the eraser
    for (int i = lines.size() - 1; i >= 0; i--) {
      LineSegment line = lines.get(i);
      if (line.intersectsCircle(x, y, radius)) {
        lines.remove(i);
      }
    }
  }
  
  // Get bounds of all lines
  float getMaxY() {
    float maxY = 0;
    for (LineSegment line : lines) {
      maxY = max(maxY, line.getMaxY());
    }
    return maxY;
  }
  
  float getMinY() {
    float minY = Float.MAX_VALUE;
    for (LineSegment line : lines) {
      minY = min(minY, line.getMinY());
    }
    return minY == Float.MAX_VALUE ? 0 : minY;
  }
  
  // Save line data to file
  void saveToFile(String filename) {
    ArrayList<String> data = new ArrayList<String>();
    
    // Save header info
    data.add("LINE_CANVAS_V1");
    data.add("animationIntensity:" + animationIntensity);
    data.add("lineCount:" + lines.size());
    
    // Save each line segment
    for (LineSegment line : lines) {
      String lineData = "LINE:";
      lineData += line.strokeColor + ",";
      lineData += line.strokeWeight + ",";
      lineData += line.animationIntensity + ",";
      lineData += line.points.size() + ",";
      
      // Save points
      for (PVector p : line.points) {
        lineData += p.x + "," + p.y + ",";
      }
      
      data.add(lineData);
    }
    
    // Save to file
    saveStrings(filename, data.toArray(new String[0]));
  }
  
  // Load line data from file
  void loadFromFile(String filename) {
    try {
      String[] data = loadStrings(filename);
      if (data == null || data.length == 0) return;
      
      // Clear existing lines
      lines.clear();
      activeLines.clear();
      
      // Check header
      if (!data[0].equals("LINE_CANVAS_V1")) return;
      
      // Parse data
      for (int i = 1; i < data.length; i++) {
        String line = data[i];
        
        if (line.startsWith("animationIntensity:")) {
          animationIntensity = Float.parseFloat(line.split(":")[1]);
        } else if (line.startsWith("LINE:")) {
          // Parse line segment
          String[] parts = line.substring(5).split(",");
          if (parts.length >= 4) {
            int col = Integer.parseInt(parts[0]);
            float weight = Float.parseFloat(parts[1]);
            float animIntensity = Float.parseFloat(parts[2]);
            int pointCount = Integer.parseInt(parts[3]);
            
            if (parts.length >= 4 + pointCount * 2) {
              // Create line segment
              float firstX = Float.parseFloat(parts[4]);
              float firstY = Float.parseFloat(parts[5]);
              LineSegment segment = new LineSegment(firstX, firstY, col, weight, animIntensity);
              
              // Add remaining points
              for (int j = 1; j < pointCount; j++) {
                float x = Float.parseFloat(parts[4 + j * 2]);
                float y = Float.parseFloat(parts[4 + j * 2 + 1]);
                segment.addPoint(x, y);
              }
              
              lines.add(segment);
            }
          }
        }
      }
    } catch (Exception e) {
      println("Error loading line canvas: " + e.getMessage());
    }
  }
}

// Individual line segment (a continuous stroke)
class LineSegment {
  ArrayList<PVector> points;
  color strokeColor;
  float strokeWeight;
  float creationTime;
  float randomSeed;  // Unique random seed for this line
  float phaseOffset; // Random phase offset for this line
  float directionX;  // Random X direction multiplier
  float directionY;  // Random Y direction multiplier
  float animationIntensity; // Store the intensity when this line was created
  float lineWaveTime; // Per-line animation time
  boolean isRainbow = false; // If true, color cycles over time
  
  LineSegment(float x, float y) {
    points = new ArrayList<PVector>();
    points.add(new PVector(x, y));
    strokeColor = color(0); // Default black
    strokeWeight = 2.0;
    creationTime = millis() * 0.001; // Store creation time for animation
    animationIntensity = 0.5; // Default animation intensity
    initRandomParams();
  }
  
  LineSegment(float x, float y, color c, float weight) {
    points = new ArrayList<PVector>();
    points.add(new PVector(x, y));
    strokeColor = c;
    strokeWeight = weight;
    creationTime = millis() * 0.001;
    animationIntensity = 0.5; // Default animation intensity
    initRandomParams();
  }
  
  LineSegment(float x, float y, color c, float weight, float intensity) {
    points = new ArrayList<PVector>();
    points.add(new PVector(x, y));
    strokeColor = c;
    strokeWeight = weight;
    creationTime = millis() * 0.001;
    animationIntensity = intensity;
    initRandomParams();
  }
  
  void initRandomParams() {
    // Initialize random parameters for unique animation
    randomSeed = random(1000);
    phaseOffset = random(TWO_PI);
    directionX = random(-1, 1);  // Random X direction
    directionY = random(-1, 1);  // Random Y direction
    lineWaveTime = 0; // Start at 0 for each line
    // animationIntensity is already set by constructor, don't override it here
  }
  
  // Update this line's animation time based on its own intensity
  void updateAnimation(float deltaTime) {
    lineWaveTime += deltaTime * animationIntensity;
  }
  
  // Add a point to this line segment
  void addPoint(float x, float y) {
    // Only add if it's different from the last point
    if (points.size() > 0) {
      PVector lastPoint = points.get(points.size() - 1);
      if (dist(x, y, lastPoint.x, lastPoint.y) > 0.5) {
        points.add(new PVector(x, y));
        
        // Limit points per segment for performance
        if (points.size() > 500) {
          // Simplify by removing every other point
          ArrayList<PVector> simplified = new ArrayList<PVector>();
          for (int i = 0; i < points.size(); i += 2) {
            simplified.add(points.get(i));
          }
          // Always keep the last point
          if (points.size() % 2 == 0) {
            simplified.add(points.get(points.size() - 1));
          }
          points = simplified;
        }
      }
    }
  }
  
  // Check if this line is visible in the viewport
  boolean isVisible(float viewportY, float viewportHeight) {
    float minY = getMinY();
    float maxY = getMaxY();
    return !(maxY < viewportY || minY > viewportY + viewportHeight);
  }
  
  // Get bounds
  float getMaxY() {
    float maxY = -Float.MAX_VALUE;
    for (PVector p : points) {
      maxY = max(maxY, p.y);
    }
    return maxY;
  }
  
  float getMinY() {
    float minY = Float.MAX_VALUE;
    for (PVector p : points) {
      minY = min(minY, p.y);
    }
    return minY;
  }
  
  // Check if this line intersects with a circle (eraser)
  boolean intersectsCircle(float cx, float cy, float radius) {
    // Check if any point in the line is within the circle
    for (PVector p : points) {
      float dist = dist(p.x, p.y, cx, cy);
      if (dist <= radius) {
        return true;
      }
    }
    
    // Also check line segments between points
    if (points.size() > 1) {
      for (int i = 0; i < points.size() - 1; i++) {
        PVector p1 = points.get(i);
        PVector p2 = points.get(i + 1);
        
        // Check if line segment intersects circle
        if (lineCircleIntersect(p1.x, p1.y, p2.x, p2.y, cx, cy, radius)) {
          return true;
        }
      }
    }
    
    return false;
  }
  
  // Check if a line segment intersects a circle
  boolean lineCircleIntersect(float x1, float y1, float x2, float y2, float cx, float cy, float radius) {
    // Vector from p1 to p2
    float dx = x2 - x1;
    float dy = y2 - y1;
    
    // Vector from p1 to circle center
    float fx = x1 - cx;
    float fy = y1 - cy;
    
    float a = dx * dx + dy * dy;
    float b = 2 * (fx * dx + fy * dy);
    float c = (fx * fx + fy * fy) - radius * radius;
    
    float discriminant = b * b - 4 * a * c;
    if (discriminant < 0) {
      return false; // No intersection
    }
    
    // Check if intersection point is on the line segment
    discriminant = sqrt(discriminant);
    float t1 = (-b - discriminant) / (2 * a);
    float t2 = (-b + discriminant) / (2 * a);
    
    if ((t1 >= 0 && t1 <= 1) || (t2 >= 0 && t2 <= 1)) {
      return true;
    }
    
    return false;
  }
  
  // Draw with Vib-Ribbon style wave animation
  void drawAnimated(PGraphics canvas, float waveTime, float amplitude, float frequency, float viewportY) {
    // Handle single point (dot) drawing
    if (points.size() == 1) {
      PVector p = points.get(0);
      
      // Apply animation only if intensity > 0
      float offsetX = 0;
      float offsetY = 0;
      
      if (animationIntensity > 0) {
        float phase = phaseOffset + lineWaveTime * 2.0;  // Use per-line time
        offsetX = sin(phase + randomSeed) * amplitude * directionX * animationIntensity;
        offsetY = cos(phase * 1.3 + randomSeed * 0.7) * amplitude * directionY * animationIntensity;
      }
      
      // Set dynamic rainbow stroke color if enabled
      if (isRainbow) {
        // Cycle hue over time; offset by randomSeed so lines differ
        float h = (lineWaveTime * 0.2 + (randomSeed * 0.137)) % 1.0; // 0..1
        if (h < 0) h += 1.0;
        canvas.colorMode(HSB, 1.0);
        canvas.stroke(h, 1.0, 1.0);
        canvas.colorMode(RGB, 255);
      } else {
        canvas.stroke(strokeColor);
      }
      canvas.strokeWeight(strokeWeight * 2); // Make dots more visible
      canvas.point(p.x + offsetX, p.y - viewportY + offsetY);
      return;
    }
    
    if (points.size() < 2) return;
    
    // Set stroke color (dynamic if rainbow)
    if (isRainbow) {
      float h = (lineWaveTime * 0.2 + (randomSeed * 0.137)) % 1.0;
      if (h < 0) h += 1.0;
      canvas.colorMode(HSB, 1.0);
      canvas.stroke(h, 1.0, 1.0);
      canvas.colorMode(RGB, 255);
    } else {
      canvas.stroke(strokeColor);
    }
    canvas.strokeWeight(strokeWeight);
    canvas.beginShape();
    
    for (int i = 0; i < points.size(); i++) {
      PVector p = points.get(i);
      
      // Apply animation only if intensity > 0
      float offsetX = 0;
      float offsetY = 0;
      
      if (animationIntensity > 0) {
        // Each line has unique movement based on its random parameters
        float phase = phaseOffset + (p.x * frequency + p.y * frequency * 0.3 + lineWaveTime * 2.0 + randomSeed);
        
        // Multi-directional movement using the line's unique direction vectors
        float wave1 = sin(phase) * amplitude;
        float wave2 = sin(phase * 3.2 + randomSeed) * (amplitude * 0.3);
        float wave3 = cos(phase * 1.7 + randomSeed * 2) * (amplitude * 0.2);
        
        // Apply directional movement - each line moves in its own direction
        offsetX = (wave1 * directionX + wave2 * abs(directionX) * 0.5) * animationIntensity;
        offsetY = (wave1 * directionY + wave2 * abs(directionY) * 0.5 + wave3) * animationIntensity;
        
        // Add some circular/spiral motion for variety
        float spiralPhase = lineWaveTime + randomSeed * TWO_PI;
        offsetX += cos(spiralPhase) * amplitude * 0.3 * directionX * animationIntensity;
        offsetY += sin(spiralPhase * 1.3) * amplitude * 0.3 * directionY * animationIntensity;
      }
      
      // Draw vertex with animated offset
      float drawX = p.x + offsetX;
      float drawY = p.y - viewportY + offsetY;
      
      if (i == 0) {
        canvas.vertex(drawX, drawY);
      } else {
        // Add curve for smoother lines
        PVector prev = points.get(i - 1);
        float prevOffsetX = 0;
        float prevOffsetY = 0;
        
        if (animationIntensity > 0) {
          float prevPhase = phaseOffset + (prev.x * frequency + prev.y * frequency * 0.3 + lineWaveTime * 2.0 + randomSeed);
          float prevWave1 = sin(prevPhase) * amplitude;
          float prevWave2 = sin(prevPhase * 3.2 + randomSeed) * (amplitude * 0.3);
          float prevWave3 = cos(prevPhase * 1.7 + randomSeed * 2) * (amplitude * 0.2);
          
          prevOffsetX = (prevWave1 * directionX + prevWave2 * abs(directionX) * 0.5) * animationIntensity;
          prevOffsetY = (prevWave1 * directionY + prevWave2 * abs(directionY) * 0.5 + prevWave3) * animationIntensity;
          
          float spiralPhase = lineWaveTime + randomSeed * TWO_PI;
          prevOffsetX += cos(spiralPhase) * amplitude * 0.3 * directionX * animationIntensity;
          prevOffsetY += sin(spiralPhase * 1.3) * amplitude * 0.3 * directionY * animationIntensity;
        }
        
        float prevDrawX = prev.x + prevOffsetX;
        float prevDrawY = prev.y - viewportY + prevOffsetY;
        
        // Use curveVertex for smooth curves
        canvas.curveVertex(prevDrawX, prevDrawY);
        canvas.curveVertex(drawX, drawY);
      }
    }
    
    // Close the shape properly
    if (points.size() > 2) {
      PVector last = points.get(points.size() - 1);
      float lastOffsetX = 0;
      float lastOffsetY = 0;
      
      if (animationIntensity > 0) {
        float lastPhase = phaseOffset + (last.x * frequency + last.y * frequency * 0.3 + lineWaveTime * 2.0 + randomSeed);
        float lastWave = sin(lastPhase) * amplitude;
        lastOffsetX = lastWave * directionX * animationIntensity;
        lastOffsetY = lastWave * directionY * animationIntensity;
      }
      
      canvas.curveVertex(last.x + lastOffsetX, last.y - viewportY + lastOffsetY);
    }
    
    canvas.endShape();
  }
  
  // Draw without animation (for debugging)
  void drawStatic(PGraphics canvas, float viewportY) {
    if (points.size() < 2) return;
    
    canvas.stroke(strokeColor);
    canvas.strokeWeight(strokeWeight);
    canvas.beginShape();
    canvas.noFill();
    
    for (PVector p : points) {
      canvas.vertex(p.x, p.y - viewportY);
    }
    
    canvas.endShape();
  }
}