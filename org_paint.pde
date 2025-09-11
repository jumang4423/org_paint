// Infinite Canvas Painting App (Simplified Version)
// For thermal printer output (576px width)

ArrayList<PGraphics> chunks;
ArrayList<Integer> chunkPositions;

// Canvas settings
final int CANVAS_WIDTH = 576;
final int CHUNK_HEIGHT = 1024;
final int SCREEN_HEIGHT = 324; // 16:9 ratio based on width

// Drawing state
boolean isDrawing = false;
boolean isErasing = false;
float brushSize = 20.0;
float scrollY = 0;
float scrollVelocity = 0;

// Mouse state
PVector prevMouse = new PVector(-1, -1);
PVector globalPrevMouse = new PVector(-1, -1);

void setup() {
  size(576, 324, P2D);
  
  // Initialize chunks
  chunks = new ArrayList<PGraphics>();
  chunkPositions = new ArrayList<Integer>();
  
  // Create initial chunk
  createChunk(0);
  
  // Set drawing modes
  smooth(8);
  
  println("Infinite canvas initialized (Simplified Version)");
  println("Canvas width: " + CANVAS_WIDTH + "px (thermal printer width)");
  println("Controls:");
  println("  - Left click: Draw");
  println("  - Right click: Erase");
  println("  - Mouse wheel: Scroll");
  println("  - Arrow keys: Scroll up/down");
  println("  - Q/A: Increase/Decrease brush size");
  println("  - C: Clear canvas");
  println("  - S: Save canvas to file");
}

void createChunk(int yPos) {
  // Check if chunk already exists
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == yPos) return;
  }
  
  PGraphics chunk = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, JAVA2D);
  chunk.beginDraw();
  chunk.background(255);
  chunk.endDraw();
  
  chunks.add(chunk);
  chunkPositions.add(yPos);
}

PGraphics getChunkAt(int globalY) {
  int chunkY = (globalY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  
  // Ensure chunk exists
  createChunk(chunkY);
  
  // Find and return chunk
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == chunkY) {
      return chunks.get(i);
    }
  }
  
  return null;
}

void drawToChunk(float globalX, float globalY, float prevGlobalX, float prevGlobalY) {
  // Get the chunk(s) that need to be drawn to
  int startChunkY = (int)(min(globalY, prevGlobalY) - brushSize/2);
  int endChunkY = (int)(max(globalY, prevGlobalY) + brushSize/2);
  
  startChunkY = (startChunkY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  endChunkY = (endChunkY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  
  // Draw to all affected chunks
  for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
    PGraphics chunk = getChunkAt(chunkY);
    if (chunk != null) {
      float localY = globalY - chunkY;
      float localPrevY = prevGlobalY - chunkY;
      
      chunk.beginDraw();
      chunk.smooth(8);
      
      if (isErasing) {
        chunk.stroke(255);
        chunk.fill(255);
      } else {
        chunk.stroke(0);
        chunk.fill(0);
      }
      
      chunk.strokeWeight(brushSize);
      chunk.strokeCap(ROUND);
      
      if (prevGlobalX >= 0 && prevGlobalY >= 0) {
        // Draw line from previous to current position
        chunk.line(prevGlobalX, localPrevY, globalX, localY);
      } else {
        // Draw single point
        chunk.ellipse(globalX, localY, brushSize, brushSize);
      }
      
      chunk.endDraw();
    }
  }
}

void draw() {
  // Apply smooth scrolling
  if (abs(scrollVelocity) > 0.1) {
    scrollY += scrollVelocity;
    scrollY = max(0, scrollY);
    scrollVelocity *= 0.9; // Damping
  }
  
  // Apply painting if mouse is pressed
  if (isDrawing || isErasing) {
    float globalMouseX = mouseX;
    float globalMouseY = mouseY + scrollY;
    
    drawToChunk(globalMouseX, globalMouseY, globalPrevMouse.x, globalPrevMouse.y);
    
    globalPrevMouse.set(globalMouseX, globalMouseY);
  }
  
  // Display the visible portion of canvas
  background(200); // Gray background to see canvas bounds
  
  // Render visible chunks
  int startY = (int)(scrollY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  int endY = (int)((scrollY + height) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;
  
  for (int chunkY = startY; chunkY <= endY; chunkY += CHUNK_HEIGHT) {
    PGraphics chunk = getChunkAt(chunkY);
    if (chunk != null) {
      image(chunk, 0, chunkY - scrollY);
    }
  }
  
  // Draw UI overlay
  drawUI();
}

void drawUI() {
  // Draw brush preview at cursor
  noFill();
  stroke(isErasing ? color(255, 100, 100) : color(100, 100, 255));
  strokeWeight(2);
  ellipse(mouseX, mouseY, brushSize, brushSize);
  
  // Draw info text
  fill(0);
  noStroke();
  textAlign(LEFT, TOP);
  text("Mode: " + (isErasing ? "ERASE" : "DRAW"), 10, 10);
  text("Brush: " + (int)brushSize + "px", 10, 25);
  text("Scroll Y: " + (int)scrollY, 10, 40);
  text("Chunks: " + chunks.size(), 10, 55);
  text("FPS: " + (int)frameRate, 10, 70);
}

void mousePressed() {
  if (mouseButton == LEFT) {
    isDrawing = true;
    isErasing = false;
  } else if (mouseButton == RIGHT) {
    isDrawing = true;
    isErasing = true;
  }
  globalPrevMouse.set(mouseX, mouseY + scrollY);
}

void mouseReleased() {
  isDrawing = false;
  isErasing = false;
  globalPrevMouse.set(-1, -1);
}

void mouseWheel(MouseEvent event) {
  scrollVelocity += event.getCount() * 20;
}

void keyPressed() {
  switch(key) {
    case 'q':
    case 'Q':
      brushSize = min(brushSize + 5, 100);
      break;
    case 'a':
    case 'A':
      brushSize = max(brushSize - 5, 5);
      break;
    case 'c':
    case 'C':
      clearCanvas();
      break;
    case 's':
    case 'S':
      saveCanvas();
      break;
  }
  
  // Arrow key scrolling
  if (key == CODED) {
    switch(keyCode) {
      case UP:
        scrollVelocity -= 30;
        break;
      case DOWN:
        scrollVelocity += 30;
        break;
    }
  }
}

void clearCanvas() {
  for (PGraphics chunk : chunks) {
    chunk.beginDraw();
    chunk.background(255);
    chunk.endDraw();
  }
  scrollY = 0;
  scrollVelocity = 0;
  println("Canvas cleared");
}

void saveCanvas() {
  if (chunks.isEmpty()) {
    println("Nothing to save");
    return;
  }
  
  // Find the bounds of all non-empty chunks
  int minY = Integer.MAX_VALUE;
  int maxY = Integer.MIN_VALUE;
  
  for (int i = 0; i < chunks.size(); i++) {
    int chunkY = chunkPositions.get(i);
    // Check if chunk has any content (simplified check)
    minY = min(minY, chunkY);
    maxY = max(maxY, chunkY + CHUNK_HEIGHT);
  }
  
  // Create full canvas
  int totalHeight = maxY - minY;
  PGraphics fullCanvas = createGraphics(CANVAS_WIDTH, totalHeight, JAVA2D);
  fullCanvas.beginDraw();
  fullCanvas.background(255);
  
  // Draw all chunks
  for (int i = 0; i < chunks.size(); i++) {
    int chunkY = chunkPositions.get(i);
    fullCanvas.image(chunks.get(i), 0, chunkY - minY);
  }
  
  fullCanvas.endDraw();
  
  // Save the image
  String filename = "paint_" + year() + nf(month(), 2) + nf(day(), 2) + 
                    "_" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".png";
  fullCanvas.save(filename);
  println("Canvas saved as: " + filename);
  println("Dimensions: " + fullCanvas.width + "x" + fullCanvas.height);
}