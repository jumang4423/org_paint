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
  void update(float timeScale) {
    waveTime += waveSpeed * timeScale;

    for (LineSegment line : lines) {
      line.updateAnimation(waveSpeed * timeScale);
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
  
  // Snapshot current state to a string array (used for undo/save)
  String[] serializeState() {
    ArrayList<String> data = new ArrayList<String>();

    data.add("LINE_CANVAS_V1");
    data.add("animationIntensity:" + animationIntensity);
    data.add("lineCount:" + lines.size());

    for (LineSegment line : lines) {
      String lineData = "LINE:";
      lineData += line.strokeColor + ",";
      lineData += line.strokeWeight + ",";
      lineData += line.animationIntensity + ",";
      lineData += line.points.size() + ",";
      lineData += (line.isRainbow ? 1 : 0) + ",";

      for (PVector p : line.points) {
        lineData += p.x + "," + p.y + ",";
      }

      data.add(lineData);
    }

    return data.toArray(new String[0]);
  }

  // Restore state from serialized string array
  void deserializeState(String[] data) {
    lines.clear();
    activeLines.clear();

    if (data == null || data.length == 0) {
      return;
    }

    if (!data[0].equals("LINE_CANVAS_V1")) {
      return;
    }

    for (int i = 1; i < data.length; i++) {
      String line = data[i];

      if (line.startsWith("animationIntensity:")) {
        animationIntensity = Float.parseFloat(line.split(":")[1]);
      } else if (line.startsWith("LINE:")) {
        String[] parts = line.substring(5).split(",");
        if (parts.length >= 4) {
          int col = Integer.parseInt(parts[0]);
          float weight = Float.parseFloat(parts[1]);
          float animIntensity = Float.parseFloat(parts[2]);
          int pointCount = Integer.parseInt(parts[3]);

          int baseIndex = 4;
          boolean isRainbow = false;
          if (parts.length >= baseIndex + 1 + pointCount * 2) {
            // Newer serialized data includes the rainbow flag
            isRainbow = parts[baseIndex].equals("1");
            baseIndex++;
          }

          if (parts.length >= baseIndex + pointCount * 2) {
            float firstX = Float.parseFloat(parts[baseIndex]);
            float firstY = Float.parseFloat(parts[baseIndex + 1]);
            LineSegment segment = new LineSegment(firstX, firstY, col, weight, animIntensity);
            segment.isRainbow = isRainbow;

            for (int j = 1; j < pointCount; j++) {
              int coordIndex = baseIndex + j * 2;
              float x = Float.parseFloat(parts[coordIndex]);
              float y = Float.parseFloat(parts[coordIndex + 1]);
              segment.addPoint(x, y);
            }

            lines.add(segment);
          }
        }
      }
    }
  }

  // Save line data to file
  void saveToFile(String filename) {
    saveStrings(filename, serializeState());
  }

  // Load line data from file
  void loadFromFile(String filename) {
    try {
      String[] data = loadStrings(filename);
      if (data == null) return;
      deserializeState(data);
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
  static final float CHAOS_NOISE_SCALE = 0.02f;
  static final float CHAOS_TIME_SCALE = 0.6f;
  static final float CHAOS_MAGNITUDE = 1.5f;
  static final float CHAOS_FLICKER_SPEED = 7.5f;
  PVector offsetScratch = new PVector();
  
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
  
  void computeOffsetForPoint(PVector point, PVector out, float amplitude, float frequency) {
    float offsetX = 0;
    float offsetY = 0;
    
    if (animationIntensity > 0) {
      float basePhase = phaseOffset + (point.x * frequency + point.y * frequency * 0.3 + lineWaveTime * 2.0 + randomSeed);
      float wave1 = sin(basePhase) * amplitude;
      float wave2 = sin(basePhase * 3.2 + randomSeed) * (amplitude * 0.3);
      float wave3 = cos(basePhase * 1.7 + randomSeed * 2) * (amplitude * 0.2);

      offsetX = (wave1 * directionX + wave2 * abs(directionX) * 0.5) * animationIntensity;
      offsetY = (wave1 * directionY + wave2 * abs(directionY) * 0.5 + wave3) * animationIntensity;

      float spiralPhase = lineWaveTime + randomSeed * TWO_PI;
      offsetX += cos(spiralPhase) * amplitude * 0.3 * directionX * animationIntensity;
      offsetY += sin(spiralPhase * 1.3) * amplitude * 0.3 * directionY * animationIntensity;

      float chaosTime = lineWaveTime * CHAOS_TIME_SCALE + randomSeed * 10.0f;
      float noiseSample1 = noise(point.x * CHAOS_NOISE_SCALE + chaosTime,
                                 point.y * CHAOS_NOISE_SCALE * 0.7f - chaosTime);
      float noiseSample2 = noise(point.y * CHAOS_NOISE_SCALE * 1.3f - chaosTime * 0.6f,
                                 point.x * CHAOS_NOISE_SCALE * 0.5f + chaosTime * 0.4f);

      float chaosAmount = amplitude * (CHAOS_MAGNITUDE + animationIntensity * 0.6f);
      offsetX += (noiseSample1 - 0.5f) * chaosAmount;
      offsetY += (noiseSample2 - 0.5f) * chaosAmount;

      float flickerPhase = lineWaveTime * CHAOS_FLICKER_SPEED + randomSeed * 5.0f;
      float flicker = sin(flickerPhase);
      offsetX += sin(basePhase * 4.5f) * amplitude * 0.25f * flicker * animationIntensity;
      offsetY += cos(basePhase * 3.7f) * amplitude * 0.25f * (1.0f - flicker * 0.5f) * animationIntensity;

      float shake = (noise(chaosTime * 0.5f, randomSeed) - 0.5f) * amplitude * 0.5f * animationIntensity;
      offsetX += shake;
      offsetY -= shake * 0.6f;
    }

    out.set(offsetX, offsetY);
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
      computeOffsetForPoint(p, offsetScratch, amplitude, frequency);
      
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
      canvas.point(p.x + offsetScratch.x, p.y - viewportY + offsetScratch.y);
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
    float prevDrawX = 0;
    float prevDrawY = 0;
    
    for (int i = 0; i < points.size(); i++) {
      PVector p = points.get(i);
      computeOffsetForPoint(p, offsetScratch, amplitude, frequency);
      float drawX = p.x + offsetScratch.x;
      float drawY = p.y - viewportY + offsetScratch.y;
      
      if (i == 0) {
        canvas.vertex(drawX, drawY);
      } else {
        // Use curveVertex for smooth curves with chaotic wobble
        canvas.curveVertex(prevDrawX, prevDrawY);
        canvas.curveVertex(drawX, drawY);
      }
      
      prevDrawX = drawX;
      prevDrawY = drawY;
    }
    
    // Close the shape properly
    if (points.size() > 2) {
      canvas.curveVertex(prevDrawX, prevDrawY);
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
