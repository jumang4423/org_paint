// Infinite Canvas Painting App - GLSL Version (OPTIMIZED)
// For thermal printer output (576px width)
// ALL rendering done with GLSL shaders

import java.io.*;
import javax.sound.midi.*;
import processing.opengl.*;

PShader paintShader;
ArrayList<PGraphics> chunkTextures;  // GPU textures
ArrayList<PGraphics> chunkBuffers;   // Ping-pong buffers
ArrayList<Integer> chunkPositions;

// Canvas settings
final int CANVAS_WIDTH = 576;
final int CHUNK_HEIGHT = 256;  // Smaller chunks for better memory usage
int SCREEN_HEIGHT = 324;  // Will be recalculated based on screen
final int MAX_CHUNKS = 50;  // Can have more chunks since they're smaller

// Drawing state
boolean isDrawing = false;
boolean isErasing = false;
float brushSize = 2.0;  // Default 2px
float scrollY = 0;
boolean pendingSave = false;  // Flag for deferred save operation
boolean pendingPrint = false;  // Flag for print after save
boolean showDebugInfo = false;  // Toggle debug info with Tab key

// Pen modes
int PEN_MODE_DEFAULT = 0;
int PEN_MODE_REMOVE = 1;
int PEN_MODE_IMAGE = 2;
int currentPenMode = PEN_MODE_DEFAULT;
String[] penModeNames = {"DEFAULT", "REMOVE", "IMAGE"};

// Color palette
int currentColorIndex = 0;  // 0=black, 1=green, 2=yellow, 3=lightgray, 4=rainbow
color[] palette = new color[5];
String[] colorNames = {"BLACK", "GREEN", "YELLOW", "LIGHT GRAY", "RAINBOW"};

// Modal system
String modalMessage = "";
int modalStartTime = 0;
int modalDuration = 1000;  // Default 1 second
boolean modalVisible = false;
boolean modalPersistent = false;  // Keep modal visible until manually cleared
boolean modalShowColorPalette = false;  // Show color palette in modal
boolean modalShowBrush = false;  // Show brush circle in modal
boolean modalShowPenMode = false;  // Show pen mode icons in modal
boolean modalShowImagePreview = false;  // Show image preview in modal

// Zoom state
boolean isSelectingZoom = false;  // Currently selecting zoom area
boolean isZoomed = false;  // Currently in zoomed view
PVector zoomSelectionStart = new PVector(-1, -1);
PVector zoomSelectionEnd = new PVector(-1, -1);
float zoomScale = 1.0;
float zoomOffsetX = 0;
float zoomOffsetY = 0;

// Mouse state for shader
PVector currentMouse = new PVector(-1, -1);
PVector prevMouse = new PVector(-1, -1);

// Undo/Redo state (single history)
ArrayList<PGraphics> undoChunkTextures;  // Store previous state
ArrayList<PGraphics> redoChunkTextures;  // Store state for redo
boolean hasUndo = false;
boolean hasRedo = false;
boolean captureUndoState = false;  // Flag to capture state before next paint
boolean pendingUndo = false;  // Defer undo to draw loop
boolean pendingRedo = false;  // Defer redo to draw loop

// Scaling for display
PGraphics lowResCanvas;
PGraphics rainbowBuffer;  // Cache for rainbow pattern
int rainbowUpdateCounter = 0;
float displayScale = 1.0;

// MIDI
MidiDevice midiDevice = null;
boolean midiConnected = false;
volatile float pendingBrushSize = -1;  // Thread-safe variable for MIDI updates
volatile int pendingColorIndex = -1;  // Thread-safe variable for color selection
volatile int pendingPenMode = -1;  // Thread-safe variable for pen mode selection
volatile int pendingImageIndex = -1;  // Thread-safe variable for image selection
volatile float pendingImageSize = -1;  // Thread-safe variable for image size
int lastMidiCheck = 0;
float lastKnownBrushSize = 2.0;  // Track last brush size to detect changes

// Image pen variables
PImage[] stampImages;
String[] stampImageNames = {"smile.png"};
int currentImageIndex = 0;
float imageStampSize = 32.0;  // Default 32px
boolean modalShowImageSelect = false;  // Show image selection in modal

void setup() {
  fullScreen(P3D);  // Fullscreen
  noSmooth();  // Disable antialiasing for pixel-perfect rendering
  hint(DISABLE_TEXTURE_MIPMAPS);  // Disable mipmaps for sharp pixels
  ((PGraphicsOpenGL)g).textureSampling(2);  // Nearest neighbor sampling
  
  // Calculate scale to fill screen width (prioritize full 576px width accessibility)
  displayScale = (float)width / CANVAS_WIDTH;
  
  // Calculate screen height based on actual window height
  SCREEN_HEIGHT = (int)(height / displayScale);
  
  // Create low-res canvas for actual drawing (full screen height)
  lowResCanvas = createGraphics(CANVAS_WIDTH, SCREEN_HEIGHT, P3D);
  lowResCanvas.noSmooth();  // No antialiasing on low-res canvas too
  
  // Create rainbow buffer for background pattern
  rainbowBuffer = createGraphics(CANVAS_WIDTH, SCREEN_HEIGHT, P3D);
  rainbowBuffer.noSmooth();
  
  // Initialize GPU texture arrays
  chunkTextures = new ArrayList<PGraphics>();
  chunkBuffers = new ArrayList<PGraphics>();
  chunkPositions = new ArrayList<Integer>();
  
  // Initialize undo/redo arrays
  undoChunkTextures = new ArrayList<PGraphics>();
  redoChunkTextures = new ArrayList<PGraphics>();
  
  // Initialize color palette
  palette[0] = color(0, 0, 0);       // Black
  palette[1] = color(0, 255, 0);     // Green  
  palette[2] = color(200, 200, 0);   // Darker Yellow (better for printing)
  palette[3] = color(192, 192, 192); // Light gray
  palette[4] = color(255, 0, 255);   // Rainbow (will be handled specially in shader)
  
  // Load final GLSL paint shader
  paintShader = loadShader("paint_final_frag.glsl");
  
  // Create initial chunk
  createGPUChunk(0);
  
  // Initialize MIDI
  initMIDI();
  
  // Set a reasonable frame rate to save CPU
  frameRate(60);
  
  println("GLSL-based infinite canvas initialized (optimized)");
  println("Canvas width: " + CANVAS_WIDTH + "px");
  println("On-demand GPU rendering enabled");
  println("Max chunks: " + MAX_CHUNKS);
  // Load stamp images
  stampImages = new PImage[stampImageNames.length];
  for (int i = 0; i < stampImageNames.length; i++) {
    stampImages[i] = loadImage(stampImageNames[i]);
    if (stampImages[i] != null) {
      println("Loaded stamp image: " + stampImageNames[i] + " (" + stampImages[i].width + "x" + stampImages[i].height + ")");
    }
  }
  
  println("Controls:");
  println("  - Left click: Draw/Remove/Stamp (based on current pen mode)");
  println("  - Right click: No action");
  println("  - Mouse wheel/Arrow keys: Scroll");
  println("  - P: Save and Print to thermal printer");
  println("  - Space: Toggle zoom mode (select area with mouse, Space again to exit)");
  println("  - Tab (hold): Show debug info");
  println("  - Cmd+Z: Undo last action");
  println("  - Cmd+Shift+Z: Redo last action");
  if (midiConnected) {
    println("  - MIDI CC1: Pen mode (Default, Remove, Image)");
    println("  - MIDI CC2: Color/Image selection");
    println("  - MIDI CC3: Brush/Image size (1-8px for brush, 10-128px for image)");
  }
}

// Save current canvas state for undo
void saveUndoState() {
  // Clear previous undo state
  for (PGraphics g : undoChunkTextures) {
    if (g != null) g.dispose();
  }
  undoChunkTextures.clear();
  
  // Copy all current chunks
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height, P3D);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    undoChunkTextures.add(copy);
  }
  
  hasUndo = true;
  hasRedo = false;  // Clear redo when new action is performed
  
  // Clear redo state
  for (PGraphics g : redoChunkTextures) {
    if (g != null) g.dispose();
  }
  redoChunkTextures.clear();
}

// Perform undo operation
void performUndo() {
  if (!hasUndo || undoChunkTextures.isEmpty()) return;
  
  // Save current state for redo
  for (PGraphics g : redoChunkTextures) {
    if (g != null) g.dispose();
  }
  redoChunkTextures.clear();
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height, P3D);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    redoChunkTextures.add(copy);
  }
  
  // Restore undo state
  for (int i = 0; i < min(chunkTextures.size(), undoChunkTextures.size()); i++) {
    PGraphics undoChunk = undoChunkTextures.get(i);
    PGraphics currentChunk = chunkTextures.get(i);
    currentChunk.beginDraw();
    currentChunk.image(undoChunk, 0, 0);
    currentChunk.endDraw();
  }
  
  hasRedo = true;
  hasUndo = false;
}

// Perform redo operation
void performRedo() {
  if (!hasRedo || redoChunkTextures.isEmpty()) return;
  
  // Save current state for undo
  for (PGraphics g : undoChunkTextures) {
    if (g != null) g.dispose();
  }
  undoChunkTextures.clear();
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height, P3D);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    undoChunkTextures.add(copy);
  }
  
  // Restore redo state
  for (int i = 0; i < min(chunkTextures.size(), redoChunkTextures.size()); i++) {
    PGraphics redoChunk = redoChunkTextures.get(i);
    PGraphics currentChunk = chunkTextures.get(i);
    currentChunk.beginDraw();
    currentChunk.image(redoChunk, 0, 0);
    currentChunk.endDraw();
  }
  
  hasUndo = true;
  hasRedo = false;
}

void createGPUChunk(int yPos) {
  // Check if already exists
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == yPos) return;
  }
  
  // OPTIMIZATION: Limit chunks to prevent memory bloat
  if (chunkPositions.size() >= MAX_CHUNKS) {
    println("Chunk limit reached (" + MAX_CHUNKS + " chunks max)");
    return;
  }
  
  // Create two GPU textures for ping-pong
  PGraphics texture = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, P3D);
  PGraphics buffer = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT, P3D);
  
  // No antialiasing on chunks
  texture.noSmooth();
  buffer.noSmooth();
  
  // Initialize to white
  texture.beginDraw();
  texture.background(255);
  texture.endDraw();
  
  buffer.beginDraw();
  buffer.background(255);
  buffer.endDraw();
  
  chunkTextures.add(texture);
  chunkBuffers.add(buffer);
  chunkPositions.add(yPos);
}

int getChunkIndex(float globalY) {
  // Don't create chunks for negative positions
  if (globalY < 0) return -1;
  
  int chunkY = ((int)globalY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  
  // Ensure chunk exists
  createGPUChunk(chunkY);
  
  // Find chunk index
  for (int i = 0; i < chunkPositions.size(); i++) {
    if (chunkPositions.get(i) == chunkY) {
      return i;
    }
  }
  return -1;
}

void applyPaintToChunk(int chunkIndex, float globalMouseX, float globalMouseY,
                       float globalPrevX, float globalPrevY) {
  if (chunkIndex < 0) return;
  
  int chunkY = chunkPositions.get(chunkIndex);
  float localMouseY = globalMouseY - chunkY;
  float localPrevY = globalPrevY - chunkY;
  
  // Check if brush/image affects this chunk
  float effectRadius = (currentPenMode == PEN_MODE_IMAGE) ? imageStampSize * 0.5 : brushSize * 0.5;
  if (localMouseY < -effectRadius - 10 || localMouseY > CHUNK_HEIGHT + effectRadius + 10) {
    return;
  }
  
  // Ping-pong: swap textures
  PGraphics currentTexture = chunkTextures.get(chunkIndex);
  PGraphics bufferTexture = chunkBuffers.get(chunkIndex);
  
  // Set shader uniforms
  paintShader.set("u_mouse", globalMouseX, localMouseY);
  paintShader.set("u_prevMouse", globalPrevX < 0 ? -1.0 : globalPrevX, 
                                 globalPrevX < 0 ? -1.0 : localPrevY);
  paintShader.set("u_brushSize", brushSize);
  paintShader.set("u_isErasing", isErasing ? 1.0 : 0.0);
  
  // Set image mode uniforms
  paintShader.set("u_isImageMode", currentPenMode == PEN_MODE_IMAGE ? 1.0 : 0.0);
  paintShader.set("u_imageSize", imageStampSize);
  
  // Pass stamp image if in image mode
  if (currentPenMode == PEN_MODE_IMAGE && stampImages != null && 
      currentImageIndex < stampImages.length && stampImages[currentImageIndex] != null) {
    paintShader.set("u_stampImage", stampImages[currentImageIndex]);
  }
  
  // Pass color to shader
  color currentColor = palette[currentColorIndex];
  paintShader.set("u_paintColor", red(currentColor)/255.0, green(currentColor)/255.0, blue(currentColor)/255.0);
  paintShader.set("u_isRainbow", currentColorIndex == 4 ? 1.0 : 0.0);
  paintShader.set("u_time", millis() / 1000.0);
  
  // Apply shader to buffer
  bufferTexture.beginDraw();
  bufferTexture.shader(paintShader);
  bufferTexture.image(currentTexture, 0, 0, CANVAS_WIDTH, CHUNK_HEIGHT);
  bufferTexture.endDraw();
  
  // Swap references
  chunkTextures.set(chunkIndex, bufferTexture);
  chunkBuffers.set(chunkIndex, currentTexture);
}

void draw() {
  // Check for pending save operation (must be done in draw loop for OpenGL)
  if (pendingSave) {
    saveAndPrint(pendingPrint);
    pendingSave = false;
    pendingPrint = false;
    return;  // Don't do other drawing this frame
  }
  
  // Check for pending undo/redo operations (must be done in draw loop for OpenGL)
  if (pendingUndo) {
    performUndo();
    pendingUndo = false;
  }
  if (pendingRedo) {
    performRedo();
    pendingRedo = false;
  }
  
  // Check for pending MIDI updates (thread-safe)
  if (pendingBrushSize > 0) {
    brushSize = pendingBrushSize;
    pendingBrushSize = -1;
    showBrushModal();  // Show brush modal with circle
  }
  
  if (pendingImageSize > 0) {
    imageStampSize = pendingImageSize;
    pendingImageSize = -1;
    showImageSizeModal();  // Show image size modal
  }
  
  if (pendingColorIndex >= 0) {
    currentColorIndex = pendingColorIndex;
    pendingColorIndex = -1;
    showColorPaletteModal();
  }
  
  if (pendingImageIndex >= 0) {
    currentImageIndex = pendingImageIndex;
    pendingImageIndex = -1;
    showImageSelectModal();
  }
  
  if (pendingPenMode >= 0) {
    currentPenMode = pendingPenMode;
    pendingPenMode = -1;
    showPenModeModal();
  }
  
  // Calculate max scroll based on actual content
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  maxScroll = max(0, maxScroll);
  scrollY = constrain(scrollY, 0, maxScroll);
  
  // OPTIMIZATION: Only process painting when actively drawing (and not selecting zoom)
  if ((isDrawing || isErasing) && !isSelectingZoom) {
    // Capture undo state before first paint stroke
    if (captureUndoState) {
      saveUndoState();
      captureUndoState = false;
    }
    
    // Transform mouse coordinates based on zoom state
    float globalMouseX, globalMouseY;
    
    if (isZoomed) {
      // In zoomed mode, transform mouse from screen space to zoomed canvas space
      globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
      globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
    } else {
      // Normal mode
      globalMouseX = mouseX / displayScale;
      globalMouseY = mouseY / displayScale + scrollY;
    }
    
    // Find affected chunks (use image size for image mode)
    float effectRadius = (currentPenMode == PEN_MODE_IMAGE) ? imageStampSize/2 : brushSize/2;
    int startChunk = (int)((globalMouseY - effectRadius) / CHUNK_HEIGHT) * CHUNK_HEIGHT;
    int endChunk = (int)((globalMouseY + effectRadius) / CHUNK_HEIGHT) * CHUNK_HEIGHT;
    
    for (int chunkY = startChunk; chunkY <= endChunk; chunkY += CHUNK_HEIGHT) {
      int idx = getChunkIndex(chunkY);
      if (idx >= 0) {
        applyPaintToChunk(idx, globalMouseX, globalMouseY, 
                         prevMouse.x, prevMouse.y);
      }
    }
    
    prevMouse.set(globalMouseX, globalMouseY);
  } else if (prevMouse.x >= 0) {
    // Reset when not drawing
    prevMouse.set(-1, -1);
  }
  
  // Render to low-res canvas first
  lowResCanvas.beginDraw();
  lowResCanvas.background(255);  // Start with white background
  
  // Apply zoom transformation if zoomed
  if (isZoomed) {
    lowResCanvas.pushMatrix();
    lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
    lowResCanvas.scale(zoomScale);
    lowResCanvas.noSmooth();  // Ensure no antialiasing when zoomed
  }
  
  // Render visible chunks to low-res canvas
  int startChunkY = max(0, (int)(scrollY / CHUNK_HEIGHT) * CHUNK_HEIGHT);
  int endChunkY = (int)((scrollY + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;
  
  // Track which areas have chunks for rainbow rendering
  boolean[] hasChunk = new boolean[(endChunkY - startChunkY) / CHUNK_HEIGHT + 1];
  
  for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
    boolean found = false;
    for (int i = 0; i < chunkPositions.size(); i++) {
      if (chunkPositions.get(i) == chunkY) {
        PGraphics chunk = chunkTextures.get(i);
        float renderY = chunkY - scrollY;
        lowResCanvas.image(chunk, 0, renderY);
        hasChunk[(chunkY - startChunkY) / CHUNK_HEIGHT] = true;
        found = true;
        break;
      }
    }
    
    // Draw rainbow only where no chunk exists
    if (!found) {
      float renderY = chunkY - scrollY;
      // Only draw if visible on screen
      if (renderY < SCREEN_HEIGHT && renderY + CHUNK_HEIGHT > 0) {
        drawRainbowSection(renderY, min(CHUNK_HEIGHT, SCREEN_HEIGHT - (int)renderY));
      }
    }
  }
  
  if (isZoomed) {
    lowResCanvas.popMatrix();
  }
  
  // Draw UI on low-res canvas (always on top, not zoomed)
  drawLowResUI();
  
  // Draw zoom selection rectangle if selecting
  if (isSelectingZoom && zoomSelectionStart.x >= 0) {
    // Happy bright colors only!
    float time = millis() * 0.001;  // Much faster animation (20x faster)
    color[] happyColors = {
      color(255, 255, 85),  // Bright Yellow
      color(85, 255, 255),  // Bright Cyan
      color(255, 85, 255),  // Bright Magenta
      color(85, 255, 85),   // Bright Green
      color(255, 170, 85),  // Bright Orange
      color(255, 85, 170),  // Hot Pink
      color(170, 255, 85),  // Lime
      color(85, 255, 170),  // Mint
      color(255, 255, 170), // Pale Yellow
      color(170, 255, 255), // Pale Cyan
      color(255, 170, 255), // Pale Magenta
      color(170, 170, 255)  // Sky Blue
    };
    
    float x1 = min(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y1 = min(zoomSelectionStart.y, zoomSelectionEnd.y);
    float x2 = max(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y2 = max(zoomSelectionStart.y, zoomSelectionEnd.y);
    
    // Fast cycling through happy colors
    int colorIndex = (int)(time * 10) % happyColors.length;
    
    lowResCanvas.noFill();
    lowResCanvas.stroke(happyColors[colorIndex]);
    lowResCanvas.strokeWeight(3);  // Slightly thicker for visibility
    lowResCanvas.rect(x1, y1, x2 - x1, y2 - y1);
  }
  
  lowResCanvas.endDraw();
  
  // Scale up and display (fill screen)
  background(0);
  
  pushMatrix();
  scale(displayScale);
  noSmooth();  // No antialiasing during final scaling
  image(lowResCanvas, 0, 0);
  popMatrix();
}

void drawRainbowSection(float yOffset, int height) {
  // Fast old-school dither pattern (like Amiga/C64 demos)
  float time = millis() * 0.00005;  // Very slow scroll
  
  // Classic 4x4 ordered dither for speed
  int[][] dither4 = {
    {0, 8, 2, 10},
    {12, 4, 14, 6},
    {3, 11, 1, 9},
    {15, 7, 13, 5}
  };
  
  // Bright Amiga/Commodore style colors only!
  color[] retroColors = {
    color(255, 255, 255), // White
    color(255, 255, 85),  // Yellow
    color(85, 255, 255),  // Light Cyan
    color(255, 85, 255),  // Light Magenta
    color(85, 255, 85),   // Light Green
    color(255, 85, 85),   // Light Red
    color(85, 85, 255),   // Light Blue
    color(255, 170, 85),  // Orange
    color(255, 85, 170),  // Pink
    color(170, 255, 85),  // Lime
    color(85, 255, 170),  // Mint
    color(170, 85, 255),  // Purple
    color(255, 255, 170), // Pale Yellow
    color(170, 255, 255), // Pale Cyan
    color(255, 170, 255), // Pale Magenta
    color(170, 170, 255)  // Pale Blue
  };
  
  lowResCanvas.strokeWeight(1);
  lowResCanvas.noSmooth();
  
  // Draw in 8x8 pixel blocks for MUCH better performance
  int blockSize = 8;
  for (int y = 0; y < height; y += blockSize) {
    for (int x = 0; x < CANVAS_WIDTH; x += blockSize) {
      float globalY = yOffset + y + scrollY;
      
      // Get dither position
      int dx = (x / blockSize) % 4;
      int dy = ((int)(globalY / blockSize)) % 4;
      float ditherValue = dither4[dy][dx] / 15.0;
      
      // Create diagonal scrolling bands
      float bandPos = ((globalY + x) * 0.01 + time * 100);
      int colorIndex = (int)(bandPos + ditherValue * 4) % 16;
      
      // Apply the retro color
      color c = retroColors[colorIndex];
      
      // Add scanline pattern within block
      lowResCanvas.noStroke();
      lowResCanvas.fill(c);
      lowResCanvas.rect(x, yOffset + y, blockSize, blockSize);
      
      // Add simple dither texture with lines
      if (ditherValue > 0.5) {
        lowResCanvas.stroke(lerpColor(c, color(255, 255, 255), 0.2));
        lowResCanvas.strokeWeight(1);
        // Draw some dither lines for texture
        lowResCanvas.line(x, yOffset + y + 2, x + blockSize, yOffset + y + 2);
        lowResCanvas.line(x, yOffset + y + 6, x + blockSize, yOffset + y + 6);
      }
    }
  }
}

// Show a modal message for a specified duration
void showModal(String message, int duration) {
  modalMessage = message;
  modalStartTime = millis();
  modalDuration = duration;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;  // Reset brush modal flag
  modalShowPenMode = false;  // Reset pen mode modal flag
  modalShowImagePreview = false;  // Reset image preview flag
}

// Show color palette modal
void showColorPaletteModal() {
  modalMessage = "";
  modalStartTime = millis();
  modalDuration = 1500;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = true;
  modalShowBrush = false;
  modalShowPenMode = false;
  modalShowImagePreview = false;
}

// Show brush size modal
void showBrushModal() {
  modalMessage = "";
  modalStartTime = millis();
  modalDuration = 500;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = true;
  modalShowPenMode = false;
  modalShowImagePreview = false;
}

// Show pen mode modal
void showPenModeModal() {
  modalMessage = "";
  modalStartTime = millis();
  modalDuration = 1500;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;
  modalShowPenMode = true;
  modalShowImagePreview = false;
}

// Show image selection modal with preview
void showImageSelectModal() {
  modalMessage = "";
  modalStartTime = millis();
  modalDuration = 1500;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;
  modalShowPenMode = false;
  modalShowImagePreview = true;
}

// Show image size modal
void showImageSizeModal() {
  modalMessage = "IMAGE SIZE: " + (int)imageStampSize + "px";
  modalStartTime = millis();
  modalDuration = 1000;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;
  modalShowPenMode = false;
  modalShowImagePreview = false;
}

// Show a modal with default 1 second duration
void showModal(String message) {
  showModal(message, 1000);
}

// Show a persistent modal that stays until cleared
void showPersistentModal(String message) {
  modalMessage = message;
  modalVisible = true;
  modalPersistent = true;
  modalShowColorPalette = false;  // Reset other modal types
  modalShowBrush = false;  // Reset other modal types
  modalShowPenMode = false;  // Reset other modal types
  modalShowImagePreview = false;  // Reset other modal types
}

// Clear persistent modal
void clearPersistentModal() {
  if (modalPersistent) {
    modalVisible = false;
    modalPersistent = false;
  }
}

// Draw modal if visible
void drawModal() {
  if (modalVisible) {
    // Check if modal should still be visible (only for non-persistent modals)
    if (!modalPersistent && millis() - modalStartTime > modalDuration) {
      modalVisible = false;
      return;
    }
    
    // Calculate fade out effect (last 200ms, only for non-persistent modals)
    float opacity = 255;
    if (!modalPersistent) {
      int timeLeft = modalDuration - (millis() - modalStartTime);
      if (timeLeft < 200) {
        opacity = map(timeLeft, 0, 200, 0, 255);
      }
    }
    
    // Calculate dimensions based on content
    lowResCanvas.textSize(10);
    float padding = 8;
    float boxWidth, boxHeight;
    
    if (modalShowColorPalette) {
      // For color palette, we need wider box for color squares
      boxWidth = 180;  // Fixed width for 5 colors
      boxHeight = 30;  // Height for color boxes
    } else if (modalShowBrush) {
      // For brush display
      boxWidth = 80;  // Smaller width for brush
      boxHeight = 24;  // Compact height
    } else if (modalShowPenMode) {
      // For pen mode icons
      boxWidth = 100;  // Width for 3 pen mode icons
      boxHeight = 30;  // Height for icons
    } else if (modalShowImagePreview) {
      // For image preview
      boxWidth = 80;  // Fixed size for image preview
      boxHeight = 80;  // Square for image
    } else {
      float textWidth = lowResCanvas.textWidth(modalMessage);
      boxWidth = textWidth + padding * 2;
      boxHeight = 20;  // Normal height for text
    }
    
    // Calculate modal position
    float modalX, modalY;
    
    // Center position for color palette, pen mode picker, and image preview
    if (modalShowColorPalette || modalShowPenMode || modalShowImagePreview) {
      // Center the modal
      modalX = (CANVAS_WIDTH - boxWidth) / 2;
      modalY = (SCREEN_HEIGHT - boxHeight) / 2;
    } else {
      // Smart positioning for other modals (opposite quadrant from mouse)
      float lowResMouseX = mouseX / displayScale;
      float lowResMouseY = mouseY / displayScale;
      boolean mouseInRightHalf = lowResMouseX > CANVAS_WIDTH / 2;
      boolean mouseInBottomHalf = lowResMouseY > SCREEN_HEIGHT / 2;
      
      if (mouseInRightHalf) {
        // Mouse is on right, show modal on left
        modalX = 4;
      } else {
        // Mouse is on left, show modal on right
        modalX = CANVAS_WIDTH - boxWidth - 4;
      }
      
      if (mouseInBottomHalf) {
        // Mouse is on bottom, show modal on top
        modalY = 4;
      } else {
        // Mouse is on top, show modal on bottom
        modalY = SCREEN_HEIGHT - boxHeight - 4;
      }
    }
    
    // Happy bright colors for rainbow border
    float time = millis() * 0.001;  // Fast animation
    color[] happyColors = {
      color(255, 255, 85),  // Bright Yellow
      color(85, 255, 255),  // Bright Cyan
      color(255, 85, 255),  // Bright Magenta
      color(85, 255, 85),   // Bright Green
      color(255, 170, 85),  // Bright Orange
      color(255, 85, 170),  // Hot Pink
      color(170, 255, 85),  // Lime
      color(85, 255, 170),  // Mint
      color(255, 255, 170), // Pale Yellow
      color(170, 255, 255), // Pale Cyan
      color(255, 170, 255), // Pale Magenta
      color(170, 170, 255)  // Sky Blue
    };
    
    // Fast cycling through happy colors
    int colorIndex = (int)(time * 10) % happyColors.length;
    color borderColor = happyColors[colorIndex];
    
    // Apply opacity to colors
    if (opacity < 255) {
      borderColor = color(red(borderColor), green(borderColor), blue(borderColor), opacity);
    }
    
    // Draw white background with rounded corners
    lowResCanvas.fill(255, opacity);  // White background
    lowResCanvas.noStroke();
    lowResCanvas.rect(modalX, modalY, boxWidth, boxHeight, 12, 12, 12, 12);  // Large border radius
    
    // Draw rainbow border with rounded corners
    lowResCanvas.noFill();
    lowResCanvas.stroke(borderColor);
    lowResCanvas.strokeWeight(2);
    lowResCanvas.rect(modalX, modalY, boxWidth, boxHeight, 12, 12, 12, 12);  // Large border radius
    
    // Draw content
    if (modalShowColorPalette) {
      // Check if we're in remove mode - show red X instead
      if (currentPenMode == PEN_MODE_REMOVE) {
        // Draw a big red X to indicate colors are not available
        lowResCanvas.stroke(255, 0, 0, opacity);  // Red color
        lowResCanvas.strokeWeight(3);
        float xSize = 40;
        float centerX = modalX + boxWidth / 2;
        float centerY = modalY + boxHeight / 2;
        lowResCanvas.line(centerX - xSize/2, centerY - xSize/2, centerX + xSize/2, centerY + xSize/2);
        lowResCanvas.line(centerX - xSize/2, centerY + xSize/2, centerX + xSize/2, centerY - xSize/2);
        
        // Add text below
        lowResCanvas.fill(255, 0, 0, opacity);
        lowResCanvas.noStroke();
        lowResCanvas.textAlign(CENTER, CENTER);
        lowResCanvas.textSize(8);
        lowResCanvas.text("N/A", centerX, centerY + xSize/2 + 10);
      } else {
        // Draw color palette boxes normally
        int boxSize = 20;
        int boxSpacing = 30;
        int startX = (int)(modalX + (boxWidth - (5 * boxSpacing - (boxSpacing - boxSize))) / 2);
        
        for (int i = 0; i < 5; i++) {
          int boxX = startX + i * boxSpacing;
          int boxY = (int)(modalY + boxHeight/2 - boxSize/2);
          
          // Draw color box with border and rounded corners
          if (i == 4) {
            // Rainbow - draw gradient or special pattern
            // Use animated rainbow colors
            float rainbowTime = millis() * 0.01;
            color rainbowColor = color(
              (sin(rainbowTime) * 0.5 + 0.5) * 255,
              (sin(rainbowTime + 2.094) * 0.5 + 0.5) * 255,
              (sin(rainbowTime + 4.189) * 0.5 + 0.5) * 255
            );
            lowResCanvas.fill(red(rainbowColor), green(rainbowColor), blue(rainbowColor), opacity);
          } else {
            lowResCanvas.fill(red(palette[i]), green(palette[i]), blue(palette[i]), opacity);
          }
          
          // Draw selection highlight with rainbow border
          if (i == currentColorIndex) {
            // Use the same rainbow color as the modal border
            lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
            lowResCanvas.strokeWeight(2);
          } else {
            lowResCanvas.stroke(128, opacity);  // Gray border for non-selected
            lowResCanvas.strokeWeight(1);
          }
          
          lowResCanvas.rect(boxX, boxY, boxSize, boxSize, 6, 6, 6, 6);  // Rounded corners
        }
      }
    } else if (modalShowBrush) {
      // Draw brush circle and size text
      float brushX = modalX + 20;
      float brushY = modalY + boxHeight/2;
      
      // Draw the actual brush circle
      lowResCanvas.noFill();
      lowResCanvas.stroke(0, opacity);  // Black circle
      lowResCanvas.strokeWeight(1);
      lowResCanvas.ellipse(brushX, brushY, brushSize, brushSize);
      
      // Draw size text (vertically centered)
      lowResCanvas.fill(0, opacity);
      lowResCanvas.textAlign(LEFT, CENTER);
      lowResCanvas.textSize(10);
      lowResCanvas.noStroke();
      lowResCanvas.text(": " + (int)brushSize + "px", brushX + brushSize/2 + 8, brushY - 1);  // Adjusted Y position
    } else if (modalShowPenMode) {
      // Draw pen mode icons
      int iconSize = 20;
      int iconSpacing = 30;
      int startX = (int)(modalX + (boxWidth - (3 * iconSpacing - (iconSpacing - iconSize))) / 2);
      
      for (int i = 0; i < 3; i++) {
        int iconX = startX + i * iconSpacing;
        int iconY = (int)(modalY + boxHeight/2 - iconSize/2);
        
        // Draw icon background with rounded corners
        if (i == currentPenMode) {
          // Selected mode - use rainbow border color
          lowResCanvas.fill(255, opacity);
          lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
          lowResCanvas.strokeWeight(2);
        } else {
          // Non-selected mode
          lowResCanvas.fill(240, opacity);
          lowResCanvas.stroke(128, opacity);
          lowResCanvas.strokeWeight(1);
        }
        
        lowResCanvas.rect(iconX, iconY, iconSize, iconSize, 6, 6, 6, 6);
        
        // Draw icons
        lowResCanvas.noStroke();
        if (i == PEN_MODE_DEFAULT) {
          // Draw pen icon (simple pencil shape)
          lowResCanvas.fill(0, opacity);
          // Pencil tip (triangle)
          lowResCanvas.triangle(
            iconX + iconSize/2, iconY + 3,
            iconX + iconSize/2 - 3, iconY + 8,
            iconX + iconSize/2 + 3, iconY + 8
          );
          // Pencil body (rectangle)
          lowResCanvas.rect(iconX + iconSize/2 - 2, iconY + 8, 4, 9);
        } else if (i == PEN_MODE_REMOVE) {
          // Draw eraser icon (rectangle with lines)
          lowResCanvas.fill(255, 192, 203, opacity);  // Pink eraser color
          lowResCanvas.rect(iconX + 4, iconY + 6, 12, 8, 2, 2, 2, 2);
          // Add eraser detail lines
          lowResCanvas.stroke(180, 150, 160, opacity);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(iconX + 6, iconY + 8, iconX + 14, iconY + 8);
          lowResCanvas.line(iconX + 6, iconY + 12, iconX + 14, iconY + 12);
        } else if (i == PEN_MODE_IMAGE) {
          // Draw image stamp icon (simplified smiley face or picture icon)
          lowResCanvas.fill(255, 200, 0, opacity);  // Yellow for smiley
          lowResCanvas.ellipse(iconX + iconSize/2, iconY + iconSize/2, 14, 14);
          // Eyes
          lowResCanvas.fill(0, opacity);
          lowResCanvas.ellipse(iconX + iconSize/2 - 3, iconY + iconSize/2 - 2, 2, 2);
          lowResCanvas.ellipse(iconX + iconSize/2 + 3, iconY + iconSize/2 - 2, 2, 2);
          // Smile
          lowResCanvas.noFill();
          lowResCanvas.stroke(0, opacity);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.arc(iconX + iconSize/2, iconY + iconSize/2, 8, 8, 0.2, PI - 0.2);
        }
      }
    } else if (modalShowImagePreview) {
      // Draw image preview with chroma key
      if (stampImages != null && currentImageIndex < stampImages.length && stampImages[currentImageIndex] != null) {
        PImage img = stampImages[currentImageIndex];
        
        // Draw the image with chroma key in the center of the modal
        float imageSize = min(boxWidth - 20, boxHeight - 20);  // Leave some padding
        float imageX = modalX + boxWidth / 2;
        float imageY = modalY + boxHeight / 2;
        
        // Draw with chroma key
        drawImageWithChromaKey(lowResCanvas, img, imageX, imageY, imageSize, (int)opacity);
        
        // Draw image name below
        lowResCanvas.fill(0, opacity);
        lowResCanvas.textAlign(CENTER, TOP);
        lowResCanvas.textSize(8);
        lowResCanvas.noStroke();
        lowResCanvas.text(stampImageNames[currentImageIndex], modalX + boxWidth/2, modalY + boxHeight - 15);
      }
    } else {
      // Draw text
      lowResCanvas.fill(0, opacity);  // Black text on white background
      lowResCanvas.textAlign(LEFT, TOP);
      lowResCanvas.noStroke();
      lowResCanvas.text(modalMessage, modalX + padding, modalY + 4);
    }
  }
}

void drawLowResUI() {
  // Draw UI directly on low-res canvas for pixel-perfect scaling
  
  // Brush preview (convert mouse position to low-res coordinates)
  float lowResMouseX = mouseX / displayScale;
  float lowResMouseY = mouseY / displayScale;
  
  // Draw preview based on current pen mode
  if (currentPenMode == PEN_MODE_IMAGE) {
    // Image stamp preview with chroma key
    if (stampImages != null && currentImageIndex < stampImages.length && stampImages[currentImageIndex] != null) {
      PImage img = stampImages[currentImageIndex];
      
      // Transform position if zoomed
      if (isZoomed && !isSelectingZoom) {
        float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
        float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
        
        lowResCanvas.pushMatrix();
        lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
        lowResCanvas.scale(zoomScale);
        
        // Draw image with chroma key manually
        drawImageWithChromaKey(lowResCanvas, img, canvasX, canvasY, imageStampSize, 128);
        
        // Draw outline
        lowResCanvas.noFill();
        lowResCanvas.stroke(0, 128);
        lowResCanvas.strokeWeight(1);
        lowResCanvas.rect(canvasX - imageStampSize/2, canvasY - imageStampSize/2, imageStampSize, imageStampSize);
        
        lowResCanvas.popMatrix();
      } else if (!isSelectingZoom) {
        // Normal image preview with chroma key
        drawImageWithChromaKey(lowResCanvas, img, lowResMouseX, lowResMouseY, imageStampSize, 128);
        
        // Draw outline
        lowResCanvas.noFill();
        lowResCanvas.stroke(0, 128);
        lowResCanvas.strokeWeight(1);
        lowResCanvas.rect(lowResMouseX - imageStampSize/2, lowResMouseY - imageStampSize/2, imageStampSize, imageStampSize);
      }
    }
  } else {
    // Regular brush preview
    color brushColor;
    if (currentPenMode == PEN_MODE_REMOVE) {
      brushColor = color(255, 0, 0);  // Red for remove mode
    } else if (currentColorIndex == 4) {
      // Rainbow - animated preview color
      float brushTime = millis() * 0.01;
      brushColor = color(
        (sin(brushTime) * 0.5 + 0.5) * 255,
        (sin(brushTime + 2.094) * 0.5 + 0.5) * 255,
        (sin(brushTime + 4.189) * 0.5 + 0.5) * 255
      );
    } else {
      brushColor = palette[currentColorIndex];
    }
    
    // Transform brush position if zoomed
    if (isZoomed && !isSelectingZoom) {
      float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
      float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
      
      lowResCanvas.noFill();
      lowResCanvas.stroke(brushColor);
      lowResCanvas.strokeWeight(1);  // Lighter weight
      
      // Draw brush at zoomed position
      lowResCanvas.pushMatrix();
      lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
      lowResCanvas.scale(zoomScale);
      lowResCanvas.ellipse(canvasX, canvasY, brushSize, brushSize);
      lowResCanvas.popMatrix();
    } else if (!isSelectingZoom) {
      // Normal brush preview
      lowResCanvas.noFill();
      lowResCanvas.stroke(brushColor);
      lowResCanvas.strokeWeight(1);  // Lighter weight
      lowResCanvas.ellipse(lowResMouseX, lowResMouseY, brushSize, brushSize);
    }
  }
  
  // Only show debug info if Tab key is pressed
  if (showDebugInfo) {
    // Info text - BLACK color for white background
    lowResCanvas.fill(0);  // Black text
    lowResCanvas.noStroke();
    lowResCanvas.textAlign(LEFT, TOP);
    lowResCanvas.textSize(8);  // Small pixel font size
    
    if (isSelectingZoom) {
      lowResCanvas.text("SELECTING ZOOM AREA", 2, 2);
    } else if (isZoomed) {
      lowResCanvas.text("ZOOMED: " + nf(zoomScale, 1, 1) + "x (SPACE to exit)", 2, 2);
    } else {
      lowResCanvas.text("PEN: " + penModeNames[currentPenMode], 2, 2);
    }
    
    if (currentPenMode == PEN_MODE_IMAGE) {
      lowResCanvas.text("IMAGE: " + stampImageNames[currentImageIndex] + " " + (int)imageStampSize + "px", 2, 10);
    } else {
      lowResCanvas.text("BRUSH: " + (int)brushSize + "px", 2, 10);
    }
    if (!isZoomed) {
      lowResCanvas.text("Y: " + (int)scrollY, 2, 18);
    }
    lowResCanvas.text("X: " + (int)lowResMouseX + "/" + CANVAS_WIDTH, 2, isZoomed ? 18 : 26);
    lowResCanvas.text("FPS: " + (int)frameRate, 2, isZoomed ? 26 : 34);
    if (midiConnected) {
      lowResCanvas.text("MIDI: ON", 2, isZoomed ? 34 : 42);
    }
  }
  
  // Draw modal on top of everything
  drawModal();
}

void mousePressed() {
  // If selecting zoom, record start position
  if (isSelectingZoom) {
    zoomSelectionStart.set(mouseX / displayScale, mouseY / displayScale);
    zoomSelectionEnd.set(mouseX / displayScale, mouseY / displayScale);
    return;
  }
  
  // Don't allow painting while selecting zoom
  if (isSelectingZoom) {
    return;
  }
  
  if (mouseButton == LEFT) {
    // Mark that we need to save state before first paint
    captureUndoState = true;
    isDrawing = true;
    // Set erasing based on pen mode
    isErasing = (currentPenMode == PEN_MODE_REMOVE);
  } else if (mouseButton == RIGHT) {
    // Right click does nothing now
    return;
  }
  
  // Adjust for scale and zoom
  if (isZoomed) {
    float canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
    float canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
    prevMouse.set(canvasX, canvasY);
  } else {
    prevMouse.set(mouseX / displayScale, mouseY / displayScale + scrollY);
  }
}

void mouseReleased() {
  // If we were selecting zoom, apply the zoom
  if (isSelectingZoom && zoomSelectionStart.x >= 0) {
    // Calculate zoom from selection
    float x1 = min(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y1 = min(zoomSelectionStart.y, zoomSelectionEnd.y);
    float x2 = max(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y2 = max(zoomSelectionStart.y, zoomSelectionEnd.y);
    
    float selWidth = x2 - x1;
    float selHeight = y2 - y1;
    
    // Minimum selection size to zoom (20px)
    if (selWidth > 20 && selHeight > 20) {
      // Calculate zoom scale to fit selection to screen
      float scaleX = CANVAS_WIDTH / selWidth;
      float scaleY = SCREEN_HEIGHT / selHeight;
      zoomScale = min(scaleX, scaleY);
      
      // Limit zoom scale to reasonable range (1.5x - 10x)
      zoomScale = constrain(zoomScale, 1.5, 10.0);
      
      // Calculate offset to center the selection
      float centerX = (x1 + x2) / 2;
      float centerY = (y1 + y2) / 2;
      
      // Calculate offset so that zoomed area is centered
      zoomOffsetX = CANVAS_WIDTH / 2 - centerX * zoomScale;
      zoomOffsetY = SCREEN_HEIGHT / 2 - centerY * zoomScale;
      
      // Apply zoom
      isZoomed = true;
      isSelectingZoom = false;
      clearPersistentModal();  // Clear the selection modal
      showModal("ZOOMED: " + nf(zoomScale, 1, 1) + "x", 1500);
    } else {
      // Selection too small, stay in selection mode
      zoomSelectionStart.set(-1, -1);
      zoomSelectionEnd.set(-1, -1);
    }
  } else {
    // Normal mouse release for painting
    isDrawing = false;
    isErasing = false;
    prevMouse.set(-1, -1);
  }
}

void mouseMoved() {
  // Brush preview follows mouse
}

void mouseDragged() {
  // If selecting zoom, update end position
  if (isSelectingZoom) {
    zoomSelectionEnd.set(mouseX / displayScale, mouseY / displayScale);
    return;
  }
  
  // Keep rendering while dragging
}

void mouseWheel(MouseEvent event) {
  // Disable scrolling when zoomed
  if (isZoomed) {
    return;
  }
  
  // Direct scroll, no velocity
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  scrollY += event.getCount() * 0.7;  // Back to trackpad-optimized speed
  scrollY = constrain(scrollY, 0, max(0, maxScroll));
}

void keyReleased() {
  // Hide debug info when Tab is released
  if (key == TAB) {
    showDebugInfo = false;
  }
}

void keyPressed() {
  // Handle ESC key for clean exit
  if (key == ESC) {
    key = 0;  // Prevent default ESC behavior
    exit();   // Call our custom exit method
    return;
  }
  
  // Handle Tab key to show debug info (while holding)
  if (key == TAB) {
    showDebugInfo = true;
    return;
  }
  
  // Handle Cmd+Z for undo and Cmd+Shift+Z for redo
  boolean isMac = System.getProperty("os.name").toLowerCase().contains("mac");
  boolean cmdPressed = isMac ? (keyEvent.isMetaDown()) : (keyEvent.isControlDown());
  
  if (cmdPressed) {
    if (key == 'z' || key == 'Z') {
      if (keyEvent.isShiftDown()) {
        // Cmd+Shift+Z - Redo (deferred to draw loop)
        pendingRedo = true;
      } else {
        // Cmd+Z - Undo (deferred to draw loop)
        pendingUndo = true;
      }
      return;
    }
  }
  
  // Handle Space key for zoom (toggle, not hold)
  if (key == ' ') {
    if (isZoomed) {
      // Exit zoom mode
      isZoomed = false;
      zoomScale = 1.0;
      zoomOffsetX = 0;
      zoomOffsetY = 0;
      showModal("ZOOM EXIT");
    } else if (isSelectingZoom) {
      // Cancel zoom selection
      isSelectingZoom = false;
      zoomSelectionStart.set(-1, -1);
      zoomSelectionEnd.set(-1, -1);
      clearPersistentModal();  // Clear the selection modal
      showModal("ZOOM CANCELLED");
    } else {
      // Enter zoom selection mode
      isSelectingZoom = true;
      zoomSelectionStart.set(-1, -1);
      zoomSelectionEnd.set(-1, -1);
      showPersistentModal("ZOOM: Drag to select area");
    }
    return;
  }
  
  switch(key) {
    case 'p':
    case 'P':
      // Defer save operation to draw loop (for OpenGL safety)
      pendingSave = true;
      pendingPrint = true;
      break;
  }
  
  if (key == CODED) {
    // Disable arrow key scrolling when zoomed
    if (isZoomed) {
      return;
    }
    
    float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
    if (keyCode == UP) {
      scrollY -= 20;
      scrollY = constrain(scrollY, 0, max(0, maxScroll));
    }
    if (keyCode == DOWN) {
      scrollY += 20;
      scrollY = constrain(scrollY, 0, max(0, maxScroll));
    }
  }
}


// Get the maximum Y position with actual content
float getMaxContentY() {
  if (chunkPositions.isEmpty()) return CHUNK_HEIGHT;  // Allow scrolling to see first chunk area
  
  int maxY = 0;
  for (int chunkY : chunkPositions) {
    maxY = max(maxY, chunkY + CHUNK_HEIGHT);
  }
  
  // Add one more chunk height to show the next gray area
  return maxY + CHUNK_HEIGHT;
}

void saveAndPrint(boolean printToReceipt) {
  if (chunkTextures.isEmpty()) {
    println("Nothing to save");
    return;
  }
  
  // Find bounds - only include chunks that have been drawn to
  int minY = Integer.MAX_VALUE;
  int maxY = Integer.MIN_VALUE;
  boolean hasContent = false;
  
  for (int i = 0; i < chunkPositions.size(); i++) {
    int chunkY = chunkPositions.get(i);
    // Always include all chunks for now
    minY = min(minY, chunkY);
    maxY = max(maxY, chunkY + CHUNK_HEIGHT);
    hasContent = true;
  }
  
  if (!hasContent) {
    println("No content to save");
    return;
  }
  
  // Create output image directly without using PGraphics
  PImage output = createImage(CANVAS_WIDTH, maxY - minY, RGB);
  output.loadPixels();
  
  // Fill with white background
  for (int i = 0; i < output.pixels.length; i++) {
    output.pixels[i] = color(255);
  }
  
  // Copy each chunk to the output
  for (int i = 0; i < chunkTextures.size(); i++) {
    int chunkY = chunkPositions.get(i);
    PGraphics chunk = chunkTextures.get(i);
    
    // Get the pixel data from the chunk
    chunk.loadPixels();
    
    // Copy pixels manually
    for (int y = 0; y < CHUNK_HEIGHT; y++) {
      int outputY = chunkY - minY + y;
      if (outputY >= 0 && outputY < output.height) {
        for (int x = 0; x < CANVAS_WIDTH; x++) {
          int chunkIndex = y * CANVAS_WIDTH + x;
          int outputIndex = outputY * CANVAS_WIDTH + x;
          if (chunkIndex < chunk.pixels.length && outputIndex < output.pixels.length) {
            output.pixels[outputIndex] = chunk.pixels[chunkIndex];
          }
        }
      }
    }
  }
  
  output.updatePixels();
  
  // Save main output file
  String filename = "output.png";
  output.save(filename);
  println("Saved: " + filename + " (" + CANVAS_WIDTH + "x" + (maxY-minY) + ")");
  
  // Also save timestamped copy
  String timestampedFilename = "glsl_paint_" + millis() + ".png";
  output.save(timestampedFilename);
  
  // Show save confirmation modal
  showModal("SAVED: " + filename, 2000);
  
  // Print to thermal printer if requested
  if (printToReceipt) {
    printToThermalPrinter(filename);
  }
}

void printToThermalPrinter(String filename) {
  println("Printing to thermal printer...");
  
  try {
    // Get absolute path to Python script
    String scriptPath = sketchPath("munbyn_printer.py");
    String imagePath = sketchPath(filename);
    
    // Run Python script to print
    ProcessBuilder pb = new ProcessBuilder("python3", scriptPath, imagePath);
    pb.redirectErrorStream(true);
    Process p = pb.start();
    
    // Read output
    BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
    String line;
    while ((line = reader.readLine()) != null) {
      println("Printer: " + line);
    }
    
    int exitCode = p.waitFor();
    if (exitCode == 0) {
      println("Print job sent successfully!");
    } else {
      println("Print failed with exit code: " + exitCode);
    }
    
  } catch (Exception e) {
    println("Error printing: " + e.getMessage());
    e.printStackTrace();
  }
}

// MIDI Functions using Java's built-in MIDI
void initMIDI() {
  try {
    MidiDevice.Info[] infos = MidiSystem.getMidiDeviceInfo();
    
    println("\nAvailable MIDI devices:");
    for (int i = 0; i < infos.length; i++) {
      println("[" + i + "] " + infos[i].getName() + " - " + infos[i].getDescription());
    }
    
    // Find Arduino Leonardo
    for (MidiDevice.Info info : infos) {
      if (info.getName().contains("Arduino Leonardo")) {
        MidiDevice device = MidiSystem.getMidiDevice(info);
        
        // Check if it's an input device (has transmitter)
        if (device.getMaxTransmitters() != 0) {
          device.open();
          
          // Set up receiver
          Transmitter transmitter = device.getTransmitter();
          transmitter.setReceiver(new MidiReceiver());
          
          midiDevice = device;
          midiConnected = true;
          println("\nMIDI connected to: " + info.getName());
          break;
        }
      }
    }
    
    if (!midiConnected) {
      println("Arduino Leonardo MIDI device not found or not available as input");
    }
    
  } catch (Exception e) {
    println("MIDI initialization failed: " + e.getMessage());
    e.printStackTrace();
    midiConnected = false;
  }
}

// Custom MIDI receiver class
class MidiReceiver implements Receiver {
  public void send(MidiMessage message, long timeStamp) {
    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      
      // Check for Control Change message (0xB0)
      if (sm.getCommand() == ShortMessage.CONTROL_CHANGE) {
        int channel = sm.getChannel() + 1;  // MIDI channels are 0-based
        int ccNumber = sm.getData1();
        int value = sm.getData2();
        
        // Handle CC1 for pen mode selection
        if (ccNumber == 1) {
          // Map MIDI value (0-127) to pen mode (0-2)
          // 0-42: Default pen, 43-85: Remove pen, 86-127: Image pen
          int newPenMode;
          if (value < 43) {
            newPenMode = PEN_MODE_DEFAULT;
          } else if (value < 86) {
            newPenMode = PEN_MODE_REMOVE;
          } else {
            newPenMode = PEN_MODE_IMAGE;
          }
          
          // Set pending pen mode (thread-safe)
          pendingPenMode = newPenMode;
          
          // Visual feedback
          println("MIDI CC1: value=" + value + " → Pen mode = " + penModeNames[newPenMode]);
        }
        
        // Handle CC2 for color/image selection
        if (ccNumber == 2) {
          if (currentPenMode == PEN_MODE_IMAGE) {
            // In image mode, CC2 selects the image
            // Currently we only have 1 image, but prepared for more
            int newImageIndex = 0;  // Always smile.png for now
            
            // Set pending image index (thread-safe)
            pendingImageIndex = newImageIndex;
            
            // Visual feedback
            println("MIDI CC2: value=" + value + " → Image = " + stampImageNames[newImageIndex]);
          } else {
            // In other modes, CC2 selects color
            // Map MIDI value (0-127) to color index (0-4)
            // 0-25: Black, 26-51: Green, 52-77: Yellow, 78-103: Light Gray, 104-127: Rainbow
            int newColorIndex = constrain(value * 5 / 128, 0, 4);
            
            // Set pending color index (thread-safe)
            pendingColorIndex = newColorIndex;
            
            // Visual feedback
            println("MIDI CC2: value=" + value + " → Color = " + colorNames[newColorIndex]);
          }
        }
        
        // Handle CC3 for brush/image size
        if (ccNumber == 3) {
          if (currentPenMode == PEN_MODE_IMAGE) {
            // In image mode, CC3 controls image size (10-128px)
            float newImageSize = map(value, 0, 127, 10, 128);
            newImageSize = constrain(newImageSize, 10, 128);
            
            // Set pending image size (thread-safe)
            pendingImageSize = newImageSize;
            
            // Visual feedback
            println("MIDI CC3: value=" + value + " → Image size = " + (int)newImageSize + "px");
          } else {
            // In other modes, CC3 controls brush size (1-8px)
            float newBrushSize = map(value, 0, 127, 1, 8);
            newBrushSize = constrain(newBrushSize, 1, 8);
            
            // Set pending brush size (thread-safe)
            pendingBrushSize = newBrushSize;
            
            // Visual feedback
            println("MIDI CC3: value=" + value + " → Brush size = " + (int)newBrushSize + "px");
          }
        }
      }
    }
  }
  
  public void close() {
    // Cleanup if needed
  }
}

// Helper function to draw image with blue chroma key
void drawImageWithChromaKey(PGraphics canvas, PImage img, float x, float y, float size, int alpha) {
  // Create a temporary image for chroma keyed version
  PImage chromaKeyed = createImage(img.width, img.height, ARGB);
  chromaKeyed.loadPixels();
  img.loadPixels();
  
  // Apply chroma key for blue (0, 0, 255)
  for (int i = 0; i < img.pixels.length; i++) {
    color c = img.pixels[i];
    float r = red(c);
    float g = green(c);
    float b = blue(c);
    
    // Check if pixel is blue (with some tolerance)
    float blueDiff = abs(b - 255) + abs(r - 0) + abs(g - 0);
    
    if (blueDiff < 30) {  // Blue pixel - make transparent
      chromaKeyed.pixels[i] = color(0, 0, 0, 0);
    } else {
      // Non-blue pixel - keep with specified alpha
      chromaKeyed.pixels[i] = color(r, g, b, alpha);
    }
  }
  chromaKeyed.updatePixels();
  
  // Draw the chroma keyed image
  canvas.imageMode(CENTER);
  canvas.image(chromaKeyed, x, y, size, size);
  canvas.imageMode(CORNER);
}

// Clean up on exit
void exit() {
  // Clean up MIDI device
  if (midiDevice != null && midiDevice.isOpen()) {
    try {
      midiDevice.close();
    } catch (Exception e) {
      // Ignore errors during shutdown
    }
  }
  
  // Call parent exit
  super.exit();
}