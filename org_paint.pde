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

// Line-based canvas for Vib-Ribbon style
LineCanvas lineCanvas;

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
// Export state (to avoid drawing from key events)
boolean pendingExportDialog = false;  // Flag to trigger export (Cmd+S) in draw()
PImage cachedExportImage = null;      // Image rendered on draw() thread for callback to save
boolean showDebugInfo = false;  // Toggle debug info with Tab key

// Pen modes
int PEN_MODE_DEFAULT = 0;
int PEN_MODE_REMOVE = 1;
int PEN_MODE_IMAGE = 2;
int PEN_MODE_ANIMATION = 3;
int currentPenMode = PEN_MODE_DEFAULT;
String[] penModeNames = {"DEFAULT", "REMOVE", "IMAGE", "ANIMATION"};

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

// Startup screen
boolean showStartupScreen = true;  // Show startup screen
float startupAnimTime = 0;

// MIDI
MidiDevice midiDevice = null;
boolean midiConnected = false;
volatile float pendingBrushSize = -1;  // Thread-safe variable for MIDI updates
volatile int pendingColorIndex = -1;  // Thread-safe variable for color selection
volatile int pendingPenMode = -1;  // Thread-safe variable for pen mode selection
volatile int pendingImageIndex = -1;  // Thread-safe variable for image selection
volatile float pendingImageSize = -1;  // Thread-safe variable for image size
volatile float pendingAnimationSpeed = -1;  // Thread-safe variable for line animation speed
volatile float pendingCloudDensity = -1;  // Thread-safe variable for cloud density
int lastMidiCheck = 0;
float lastKnownBrushSize = 2.0;  // Track last brush size to detect changes

// Image pen variables
PImage[] stampImages;
String[] stampImageNames = {"smile.png", "kit.gif"};
int currentImageIndex = 0;
float imageStampSize = 32.0;  // Default 32px
boolean modalShowImageSelect = false;  // Show image selection in modal

// GIF animation support (manual frame cycling)
PImage[][] gifFrames;  // Store multiple versions for animation effect
int[] currentFrameIndex;  // Current frame for each image
int[] totalFrames;  // Total number of frames for each image
int frameUpdateInterval = 38;  // Update every 38ms (~26 fps, 1.3x faster than 20fps)
int lastFrameUpdate = 0;
boolean[] isAnimated;  // Track which images are animated

// Animated pen instance
AnimatedPen animatedPen;
float animationSize = 20.0;  // Default animation size
boolean modalShowAnimationType = false;  // Show animation type in modal
boolean modalShowAnimationSelect = false;  // Show animation selection in modal

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
  
  // Initialize line canvas
  lineCanvas = new LineCanvas();
  
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
  try {
    paintShader = loadShader("paint_final_frag.glsl");
    if (paintShader == null) {
      println("WARNING: Failed to load shader, using fallback mode");
    } else {
      println("Shader loaded successfully");
    }
  } catch (Exception e) {
    println("WARNING: Error loading shader: " + e.getMessage() + ", using fallback mode");
    paintShader = null;
  }
  
  // Create initial chunk
  createGPUChunk(0);
  
  // Initialize MIDI
  initMIDI();
  
  // Set a reasonable frame rate to save CPU
  frameRate(60);
  
  // Initialize animated pen
  animatedPen = new AnimatedPen();
  
  println("GLSL-based infinite canvas initialized (optimized)");
  println("Canvas width: " + CANVAS_WIDTH + "px");
  println("On-demand GPU rendering enabled");
  println("Max chunks: " + MAX_CHUNKS);
  // Load stamp images and handle GIF animation
  stampImages = new PImage[stampImageNames.length];
  gifFrames = new PImage[stampImageNames.length][];
  currentFrameIndex = new int[stampImageNames.length];
  totalFrames = new int[stampImageNames.length];
  isAnimated = new boolean[stampImageNames.length];
  
  for (int i = 0; i < stampImageNames.length; i++) {
    String fileName = stampImageNames[i];
    
    if (fileName.equals("kit.gif")) {
      // Load actual extracted frames for kit.gif
      ArrayList<PImage> frameList = new ArrayList<PImage>();
      int frameNum = 1;
      
      // Original: 400 frames at 50 fps = 8 seconds of animation
      // Target: 20 fps playback = 8 seconds × 20 fps = 160 frames needed
      // Sample rate: 400/160 = 2.5, so take every 2.5th frame (alternating 2 and 3)
      boolean skipTwo = true;
      while (frameNum <= 400) {
        String framePath = String.format("kit_frames/kit_frame_%02d.png", frameNum);
        PImage frame = loadImage(framePath);
        if (frame != null) {
          frameList.add(frame);
        } else {
          break;  // Stop if frame not found
        }
        // Alternate between skipping 2 and 3 frames to get 2.5 average
        frameNum += skipTwo ? 2 : 3;
        skipTwo = !skipTwo;
      }
      
      if (frameList.size() > 0) {
        gifFrames[i] = frameList.toArray(new PImage[frameList.size()]);
        totalFrames[i] = gifFrames[i].length;
        stampImages[i] = gifFrames[i][0];  // Start with first frame
        isAnimated[i] = true;
        currentFrameIndex[i] = 0;
        println("Loaded animated GIF: " + fileName + " with " + totalFrames[i] + " frames at 20fps");
      } else {
        // Fallback to static image
        stampImages[i] = loadImage(fileName);
        isAnimated[i] = false;
        totalFrames[i] = 1;
        println("Failed to load frames, using static: " + fileName);
      }
    } else {
      // Regular static image
      stampImages[i] = loadImage(fileName);
      if (stampImages[i] != null) {
        ((PGraphicsOpenGL)g).textureSampling(2);  // Nearest neighbor
        println("Loaded static image: " + fileName + " (" + stampImages[i].width + "x" + stampImages[i].height + ")");
        isAnimated[i] = false;
        totalFrames[i] = 1;
      }
    }
  }
  
  println("Controls:");
  println("  - Left click: Draw/Remove/Stamp/Animate (based on current pen mode)");
  println("  - Right click: No action");
  println("  - Mouse wheel/Arrow keys: Scroll");
  println("  - P: Save and Print to thermal printer");
  println("  - Space: Toggle zoom mode (select area with mouse, Space again to exit)");
  println("  - Tab (hold): Show debug info");
  println("  - Cmd+Z: Undo last action");
  println("  - Cmd+Shift+Z: Redo last action");
  if (midiConnected) {
    println("  - MIDI CC1: Pen mode (Default, Remove, Image, Animation)");
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
  
  // Initialize to white with full opacity
  texture.beginDraw();
  texture.background(255, 255, 255);  // Explicit white
  texture.fill(255);  // Ensure fill is white
  texture.noStroke();
  texture.rect(0, 0, CANVAS_WIDTH, CHUNK_HEIGHT);  // Draw white rect to ensure coverage
  texture.endDraw();
  texture.flush();  // Ensure GPU sync
  
  buffer.beginDraw();
  buffer.background(255, 255, 255);  // Explicit white
  buffer.fill(255);  // Ensure fill is white
  buffer.noStroke();
  buffer.rect(0, 0, CANVAS_WIDTH, CHUNK_HEIGHT);  // Draw white rect to ensure coverage
  buffer.endDraw();
  buffer.flush();  // Ensure GPU sync
  
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
  
  // Animation erasing is now handled in the main draw loop
  
  // Ping-pong: swap textures
  PGraphics currentTexture = chunkTextures.get(chunkIndex);
  PGraphics bufferTexture = chunkBuffers.get(chunkIndex);
  
  // Only apply shader if it's loaded
  if (paintShader != null) {
    // Convert Y to bottom-origin for shader sampling
    float shaderMouseY = CHUNK_HEIGHT - localMouseY;
    float shaderPrevY = (globalPrevX < 0 || globalPrevY < 0) ? -1.0 : (CHUNK_HEIGHT - localPrevY);

    // Set shader uniforms
    paintShader.set("u_mouse", globalMouseX, shaderMouseY);
    paintShader.set("u_prevMouse", globalPrevX < 0 ? -1.0 : globalPrevX,
                                   shaderPrevY);
    // Use much bigger brush size for eraser
    float shaderBrushSize = isErasing ? brushSize * 5.0 : brushSize;
    paintShader.set("u_brushSize", shaderBrushSize);
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
  } else {
    // Fallback: Simple drawing without shader
    bufferTexture.beginDraw();
    bufferTexture.image(currentTexture, 0, 0);
    
    // Draw with basic Processing commands
    if (currentPenMode == PEN_MODE_IMAGE) {
      // Draw stamp image
      if (stampImages != null && currentImageIndex < stampImages.length && stampImages[currentImageIndex] != null) {
        bufferTexture.imageMode(CENTER);
        bufferTexture.image(stampImages[currentImageIndex], globalMouseX, localMouseY, imageStampSize, imageStampSize);
        bufferTexture.imageMode(CORNER);
      }
    } else {
      // Regular brush
      if (isErasing) {
        bufferTexture.stroke(255);
        bufferTexture.fill(255);
      } else {
        color currentColor = palette[currentColorIndex];
        bufferTexture.stroke(currentColor);
        bufferTexture.fill(currentColor);
      }
      
      // Use much bigger brush size for eraser
      float effectiveBrushSize = isErasing ? brushSize * 5.0 : brushSize;
      bufferTexture.strokeWeight(effectiveBrushSize);
      bufferTexture.strokeCap(ROUND);
      
      // Draw line from previous position if available
      if (globalPrevX >= 0 && globalPrevY >= 0) {
        bufferTexture.line(globalPrevX, localPrevY, globalMouseX, localMouseY);
      }
      // Also draw a circle at current position
      bufferTexture.noStroke();
      bufferTexture.ellipse(globalMouseX, localMouseY, effectiveBrushSize, effectiveBrushSize);
    }
    bufferTexture.endDraw();
  }
  
  // Swap references
  chunkTextures.set(chunkIndex, bufferTexture);
  chunkBuffers.set(chunkIndex, currentTexture);
}

void draw() {
  // Update GIF animations
  updateGifAnimations();
  
  // Update animated pen animations
  if (animatedPen != null) {
    animatedPen.update();
  }
  
  // Show startup screen if needed
  if (showStartupScreen) {
    drawStartupScreen();
    return;
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
  
  if (pendingAnimationSpeed >= -3) {
    if (pendingAnimationSpeed == -3) {
      // Show cloud density modal
      int densityPercent = (int)(pendingCloudDensity * 100);
      showModal("CLOUD DENSITY: " + densityPercent + "%", 1000);
      pendingAnimationSpeed = -1;
      pendingCloudDensity = -1;
    } else if (pendingAnimationSpeed == -2) {
      // Show disabled modal
      showModal("CC4: ✗ DISABLED", 1000);
      pendingAnimationSpeed = -1;
    } else if (pendingAnimationSpeed >= 0) {
      if (lineCanvas != null) {
        lineCanvas.setAnimationIntensity(pendingAnimationSpeed);
      }
      pendingAnimationSpeed = -1;
      // Show modal with animation speed
      int speedPercent = (int)(lineCanvas.animationIntensity * 100);
      showModal("LINE ANIM: " + speedPercent + "%", 1000);
    }
  }
  
  // Update line canvas animation
  if (lineCanvas != null) {
    lineCanvas.update();
    lineCanvas.scrollTo(scrollY);
  }
  
  // Calculate max scroll based on actual content
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  maxScroll = max(0, maxScroll);
  scrollY = constrain(scrollY, 0, maxScroll);
  
  // OPTIMIZATION: Only process painting when actively drawing (and not selecting zoom)
  if ((isDrawing || isErasing) && !isSelectingZoom) {
    // First handle special erasing for lines and animations if in REMOVE mode
    if (currentPenMode == PEN_MODE_REMOVE) {
      // Eraser mode - erase lines AND animations
      // Transform mouse coordinates
      float globalMouseX, globalMouseY;
      
      if (isZoomed) {
        globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        globalMouseX = mouseX / displayScale;
        globalMouseY = mouseY / displayScale + scrollY;
      }
      
      // Erase lines at current position with much bigger radius
      float eraserRadius = brushSize * 5;  // Make eraser much bigger
      if (lineCanvas != null) {
        lineCanvas.eraseAt(globalMouseX, globalMouseY, eraserRadius);
      }
      
      // Also erase animations (cloud pen objects) with much bigger radius
      if (animatedPen != null) {
        // Use circle eraser for animations
        animatedPen.eraseAt(globalMouseX, globalMouseY, eraserRadius, scrollY);
      }
      // Now continue to chunk processing below
    }
    
    // Handle different pen modes for drawing/erasing
    if (currentPenMode == PEN_MODE_ANIMATION) {
      // Animation pen doesn't draw to buffer, just places animations
      // This is handled in mousePressed event
    } else if (currentPenMode == PEN_MODE_DEFAULT && lineCanvas != null) {
      // Line-based drawing for default pen mode
      // Transform mouse coordinates
      float globalMouseX, globalMouseY;
      
      if (isZoomed) {
        globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        globalMouseX = mouseX / displayScale;
        globalMouseY = mouseY / displayScale + scrollY;
      }
      
      // Ensure chunk exists at this position
      int chunkY = ((int)globalMouseY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
      createGPUChunk(chunkY);
      
      // Add point to line canvas
      lineCanvas.addPoint(globalMouseX, globalMouseY);
      // If rainbow color selected, mark current stroke as rainbow so it animates colors dynamically
      if (currentColorIndex == 4) {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], true);
      } else {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], false);
      }
      lineCanvas.setWeight(brushSize);
      
      prevMouse.set(globalMouseX, globalMouseY);
    } else {
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
      
      // Find affected chunks (use image size for image mode, much bigger radius for eraser)
      float effectRadius = (currentPenMode == PEN_MODE_IMAGE) ? imageStampSize/2 : 
                          (currentPenMode == PEN_MODE_REMOVE) ? brushSize * 3 : brushSize/2;
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
    }
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
  
  // Draw line canvas with Vib-Ribbon animation (after chunks)
  if (lineCanvas != null) {
    lineCanvas.draw(lowResCanvas, isZoomed, zoomScale, zoomOffsetX, zoomOffsetY);
  }
  
  // Draw animated pen animations (after chunks, before UI)
  if (animatedPen != null) {
    animatedPen.draw(lowResCanvas, scrollY, isZoomed, zoomScale, zoomOffsetX, zoomOffsetY);
    
    // Draw deletion rectangles when in eraser mode
    if (currentPenMode == PEN_MODE_REMOVE) {
      float lowResMouseX = mouseX / displayScale;
      float lowResMouseY = mouseY / displayScale;
      
      // Calculate actual mouse position in canvas space
      float canvasMouseX, canvasMouseY;
      if (isZoomed) {
        canvasMouseX = (lowResMouseX - zoomOffsetX) / zoomScale;
        canvasMouseY = (lowResMouseY - zoomOffsetY) / zoomScale + scrollY;
      } else {
        canvasMouseX = lowResMouseX;
        canvasMouseY = lowResMouseY + scrollY;
      }
      
      // Draw X mark on ALL animations when in eraser mode
      for (AnimationInstance anim : animatedPen.animations) {
        float dist = dist(canvasMouseX, canvasMouseY, anim.originX, anim.originY);
        boolean isNear = dist < 50;  // Check if mouse is near
        
        // Draw on all animations, but highlight if mouse is near
        lowResCanvas.pushStyle();
        
        if (isZoomed) {
          lowResCanvas.pushMatrix();
          lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
          lowResCanvas.scale(zoomScale);
        }
        
        float rectX = anim.originX;
        float rectY = anim.originY - scrollY;
        float rectSize = 20;
        
        // Draw deletion indicator rectangle
        if (isNear) {
          // Highlighted when mouse is near
          lowResCanvas.fill(255, 100, 0, 80);  // Semi-transparent orange
          lowResCanvas.stroke(255, 100, 0, 200);  // Orange border
        } else {
          // Dimmed when mouse is far
          lowResCanvas.fill(255, 100, 0, 30);  // Very transparent orange
          lowResCanvas.stroke(255, 100, 0, 100);  // Dim orange border
        }
        lowResCanvas.strokeWeight(2);
        lowResCanvas.rectMode(CENTER);
        lowResCanvas.rect(rectX, rectY, rectSize, rectSize, 3);  // Slightly rounded corners
        
        // Always draw X in the center
        lowResCanvas.stroke(255, 255, 255, isNear ? 255 : 150);  // White X, dimmer when far
        lowResCanvas.strokeWeight(2);
        float halfSize = rectSize * 0.3;
        lowResCanvas.line(rectX - halfSize, rectY - halfSize, rectX + halfSize, rectY + halfSize);
        lowResCanvas.line(rectX - halfSize, rectY + halfSize, rectX + halfSize, rectY - halfSize);
        lowResCanvas.rectMode(CORNER);
        
        if (isZoomed) {
          lowResCanvas.popMatrix();
        }
        
        lowResCanvas.popStyle();
      }
    }
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
  modalShowAnimationSelect = false;  // Reset animation select flag
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
  modalShowAnimationSelect = false;
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
  modalShowAnimationSelect = false;
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
  modalShowImageSelect = false;  // Reset image select
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
  modalShowAnimationSelect = false;
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
  modalShowAnimationType = false;
  modalShowAnimationSelect = false;
}

// Show animation type modal with visual selector
void showAnimationTypeModal() {
  modalMessage = "";
  modalStartTime = millis();
  modalDuration = 1500;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;
  modalShowPenMode = false;
  modalShowImagePreview = false;
  modalShowAnimationType = false;
  modalShowAnimationSelect = true;
}

// Show animation size modal
void showAnimationSizeModal() {
  modalMessage = "ANIM SIZE: " + (int)animationSize + "px";
  modalStartTime = millis();
  modalDuration = 1000;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;
  modalShowPenMode = false;
  modalShowImagePreview = false;
  modalShowAnimationType = false;
  modalShowAnimationSelect = false;
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
  modalShowAnimationSelect = false;  // Reset other modal types
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
      // For pen mode icons (4 modes)
      boxWidth = 130;  // Width for 4 pen mode icons
      boxHeight = 30;  // Height for icons
    } else if (modalShowImagePreview) {
      // For image preview - show all images like color picker
      boxWidth = stampImageNames.length * 30 + 10;  // Width for all images
      boxHeight = 40;  // Height for image boxes
    } else if (modalShowAnimationSelect) {
      // For animation type selection - currently only 1 type
      boxWidth = animatedPen.animationTypeNames.length * 30 + 10;  // Width for animation types
      boxHeight = 40;  // Height for animation boxes
    } else {
      float textWidth = lowResCanvas.textWidth(modalMessage);
      boxWidth = textWidth + padding * 2;
      boxHeight = 20;  // Normal height for text
    }
    
    // Calculate modal position
    float modalX, modalY;
    
    // Center position for color palette, pen mode picker, image preview, and animation selector
    if (modalShowColorPalette || modalShowPenMode || modalShowImagePreview || modalShowAnimationSelect) {
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
      // Draw pen mode icons (now 4 modes)
      int iconSize = 20;
      int iconSpacing = 30;
      boxWidth = 130;  // Wider for 4 modes
      int startX = (int)(modalX + (boxWidth - (4 * iconSpacing - (iconSpacing - iconSize))) / 2);
      
      for (int i = 0; i < 4; i++) {  // Now 4 pen modes
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
        } else if (i == PEN_MODE_ANIMATION) {
          // Draw animation icon (sparkles/stars)
          lowResCanvas.stroke(100, 100, 100, opacity);
          lowResCanvas.strokeWeight(1.5);
          lowResCanvas.noFill();
          
          // Draw three sparkle/star shapes
          // Main star (larger)
          float cx1 = iconX + iconSize/2;
          float cy1 = iconY + iconSize/2;
          float starSize = 4;
          // Draw 4-point star/sparkle
          lowResCanvas.line(cx1 - starSize, cy1, cx1 + starSize, cy1);
          lowResCanvas.line(cx1, cy1 - starSize, cx1, cy1 + starSize);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(cx1 - starSize*0.7, cy1 - starSize*0.7, cx1 + starSize*0.7, cy1 + starSize*0.7);
          lowResCanvas.line(cx1 - starSize*0.7, cy1 + starSize*0.7, cx1 + starSize*0.7, cy1 - starSize*0.7);
          
          // Small star top-right
          float cx2 = iconX + iconSize/2 + 5;
          float cy2 = iconY + iconSize/2 - 3;
          float smallSize = 2;
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(cx2 - smallSize, cy2, cx2 + smallSize, cy2);
          lowResCanvas.line(cx2, cy2 - smallSize, cx2, cy2 + smallSize);
          
          // Small star bottom-left
          float cx3 = iconX + iconSize/2 - 5;
          float cy3 = iconY + iconSize/2 + 3;
          lowResCanvas.line(cx3 - smallSize, cy3, cx3 + smallSize, cy3);
          lowResCanvas.line(cx3, cy3 - smallSize, cx3, cy3 + smallSize);
        }
      }
    } else if (modalShowImagePreview) {
      // Draw all image options like color picker
      int boxSize = 24;  // Size for each image box
      int boxSpacing = 30;
      int startX = (int)(modalX + (boxWidth - (stampImageNames.length * boxSpacing - (boxSpacing - boxSize))) / 2);
      
      for (int i = 0; i < stampImageNames.length; i++) {
        int boxX = startX + i * boxSpacing;
        int boxY = (int)(modalY + boxHeight/2 - boxSize/2);
        
        // Draw selection highlight with rainbow border
        if (i == currentImageIndex) {
          // Use the same rainbow color as the modal border
          lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
          lowResCanvas.strokeWeight(2);
        } else {
          lowResCanvas.stroke(128, opacity);  // Gray border for non-selected
          lowResCanvas.strokeWeight(1);
        }
        
        // White background for image
        lowResCanvas.fill(255, opacity);
        lowResCanvas.rect(boxX, boxY, boxSize, boxSize, 6, 6, 6, 6);
        
        // Draw the image preview
        if (stampImages != null && i < stampImages.length && stampImages[i] != null) {
          // Draw image with transparency
          lowResCanvas.noSmooth();
          lowResCanvas.tint(255, opacity);
          lowResCanvas.imageMode(CENTER);
          lowResCanvas.image(stampImages[i], boxX + boxSize/2, boxY + boxSize/2, boxSize - 4, boxSize - 4);
          lowResCanvas.imageMode(CORNER);
          lowResCanvas.noTint();
        }
      }
    } else if (modalShowAnimationSelect) {
      // Draw animation type selector (currently only CLOUD)
      int boxSize = 24;  // Size for each animation type box
      int boxSpacing = 30;
      int startX = (int)(modalX + (boxWidth - (animatedPen.animationTypeNames.length * boxSpacing - (boxSpacing - boxSize))) / 2);
      
      for (int i = 0; i < animatedPen.animationTypeNames.length; i++) {
        int boxX = startX + i * boxSpacing;
        int boxY = (int)(modalY + boxHeight/2 - boxSize/2);
        
        // Draw selection highlight with rainbow border
        if (i == animatedPen.currentAnimationType) {
          // Use the same rainbow color as the modal border
          lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
          lowResCanvas.strokeWeight(2);
        } else {
          lowResCanvas.stroke(128, opacity);  // Gray border for non-selected
          lowResCanvas.strokeWeight(1);
        }
        
        // White background for icon
        lowResCanvas.fill(255, opacity);
        lowResCanvas.rect(boxX, boxY, boxSize, boxSize, 6, 6, 6, 6);
        
        // Draw cloud icon for CLOUD type
        if (i == 0) {  // CLOUD animation
          lowResCanvas.noStroke();
          lowResCanvas.fill(150, 150, 150, opacity * 0.8);  // Gray cloud
          // Draw three overlapping circles to form a cloud
          lowResCanvas.ellipse(boxX + boxSize/2 - 4, boxY + boxSize/2 + 3, 10, 10);
          lowResCanvas.ellipse(boxX + boxSize/2 + 4, boxY + boxSize/2 + 3, 10, 10);
          lowResCanvas.ellipse(boxX + boxSize/2, boxY + boxSize/2 - 2, 12, 12);
        }
        // Add more animation type icons here in the future
      }
      
      // Show animation type name below
      lowResCanvas.fill(0, opacity);
      lowResCanvas.textAlign(CENTER, TOP);
      lowResCanvas.textSize(8);
      lowResCanvas.noStroke();
      lowResCanvas.text(animatedPen.getCurrentTypeName(), modalX + boxWidth/2, modalY + boxHeight - 8);
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
  if (currentPenMode == PEN_MODE_ANIMATION) {
    // Animation preview - show horizontal ellipses with black borders like actual animation
    float time = millis() * 0.001;
    float pulseAmount = sin(time * 3) * 0.2;  // 20% pulse
    float baseSize = animationSize;
    float pulseSize = baseSize + (baseSize * pulseAmount);
    
    if (isZoomed && !isSelectingZoom) {
      float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
      float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
      
      lowResCanvas.pushMatrix();
      lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
      lowResCanvas.scale(zoomScale);
      
      // Draw pulsing cloud preview with horizontal ellipses
      float cloudScale = pulseSize / 20.0;
      
      // Black borders
      lowResCanvas.stroke(0, 0, 0, 150);  // Black border
      lowResCanvas.strokeWeight(1);
      // Lighter fill
      lowResCanvas.fill(200, 200, 200, 80);  // Lighter gray, more transparent
      
      // Horizontal ellipses (wider than tall)
      lowResCanvas.ellipse(canvasX - 5 * cloudScale, canvasY + 3 * cloudScale, pulseSize * 0.7 * 1.5, pulseSize * 0.7 * 0.7);
      lowResCanvas.ellipse(canvasX + 5 * cloudScale, canvasY + 3 * cloudScale, pulseSize * 0.7 * 1.5, pulseSize * 0.7 * 0.7);
      lowResCanvas.ellipse(canvasX, canvasY - 3 * cloudScale, pulseSize * 0.8 * 1.5, pulseSize * 0.8 * 0.7);
      
      lowResCanvas.popMatrix();
    } else if (!isSelectingZoom) {
      // Normal animation preview with horizontal ellipses
      float cloudScale = pulseSize / 20.0;
      
      // Black borders
      lowResCanvas.stroke(0, 0, 0, 150);  // Black border
      lowResCanvas.strokeWeight(1);
      // Lighter fill
      lowResCanvas.fill(200, 200, 200, 80);  // Lighter gray, more transparent
      
      // Horizontal ellipses (wider than tall)
      lowResCanvas.ellipse(lowResMouseX - 5 * cloudScale, lowResMouseY + 3 * cloudScale, pulseSize * 0.7 * 1.5, pulseSize * 0.7 * 0.7);
      lowResCanvas.ellipse(lowResMouseX + 5 * cloudScale, lowResMouseY + 3 * cloudScale, pulseSize * 0.7 * 1.5, pulseSize * 0.7 * 0.7);
      lowResCanvas.ellipse(lowResMouseX, lowResMouseY - 3 * cloudScale, pulseSize * 0.8 * 1.5, pulseSize * 0.8 * 0.7);
    }
  } else if (currentPenMode == PEN_MODE_IMAGE) {
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
        
        // Draw image with transparency
        drawImageWithTransparency(lowResCanvas, img, canvasX, canvasY, imageStampSize, 128);
        
        lowResCanvas.popMatrix();
      } else if (!isSelectingZoom) {
        // Normal image preview with transparency
        drawImageWithTransparency(lowResCanvas, img, lowResMouseX, lowResMouseY, imageStampSize, 128);
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
      // Show bigger preview circle for eraser
      float previewSize = (currentPenMode == PEN_MODE_REMOVE) ? brushSize * 5.0 : brushSize;
      lowResCanvas.ellipse(canvasX, canvasY, previewSize, previewSize);
      lowResCanvas.popMatrix();
    } else if (!isSelectingZoom) {
      // Normal brush preview
      lowResCanvas.noFill();
      lowResCanvas.stroke(brushColor);
      lowResCanvas.strokeWeight(1);  // Lighter weight
      // Show bigger preview circle for eraser
      float previewSize = (currentPenMode == PEN_MODE_REMOVE) ? brushSize * 5.0 : brushSize;
      lowResCanvas.ellipse(lowResMouseX, lowResMouseY, previewSize, previewSize);
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
    } else if (currentPenMode == PEN_MODE_ANIMATION) {
      lowResCanvas.text("ANIM: " + animatedPen.getCurrentTypeName(), 2, 10);
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
  
  // Check for pending save operation AFTER all drawing is complete
  if (pendingSave) {
    // Use a try-catch to handle any OpenGL issues
    try {
      saveAndPrint(pendingPrint);
    } catch (Exception e) {
      println("Error during save: " + e.getMessage());
      showModal("SAVE ERROR", 2000);
    }
    pendingSave = false;
    pendingPrint = false;
  }

  // Handle deferred export dialog (Cmd+S) after drawing completes
  if (pendingExportDialog) {
    try {
      // Render full canvas image on the draw thread and cache it
      cachedExportImage = renderFullCanvasToImage();
      // Open file dialog for saving
      selectOutput("Save as PNG:", "saveCanvasCallback", dataFile("canvas_" + year() + month() + day() + "_" + hour() + minute() + second() + ".png"));
    } catch (Exception e) {
      println("Error preparing export: " + e.getMessage());
      showModal("EXPORT ERROR", 2000);
    }
    pendingExportDialog = false;
  }
}

void mousePressed() {
  // Don't process mouse during startup screen
  if (showStartupScreen) return;
  
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
    // Handle animation pen click
    if (currentPenMode == PEN_MODE_ANIMATION) {
      // Calculate position
      float canvasX, canvasY;
      if (isZoomed) {
        canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale;
      } else {
        canvasX = mouseX / displayScale;
        canvasY = mouseY / displayScale;
      }
      
      // Add new animation at this position with current size
      animatedPen.addAnimation(canvasX, canvasY, scrollY, animationSize);
      isDrawing = false; // Don't continue with normal drawing
    } else if (currentPenMode == PEN_MODE_DEFAULT && lineCanvas != null) {
      // Start a new line stroke for line-based drawing
      float canvasX, canvasY;
      if (isZoomed) {
        canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        canvasX = mouseX / displayScale;
        canvasY = mouseY / displayScale + scrollY;
      }
      
      lineCanvas.startStroke(canvasX, canvasY);
      if (currentColorIndex == 4) {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], true);
      } else {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], false);
      }
      lineCanvas.setWeight(brushSize);
      isDrawing = true;
      isErasing = false;  // DEFAULT mode is not erasing
    } else if (currentPenMode == PEN_MODE_REMOVE) {
      // REMOVE mode - set flags for chunk erasing
      captureUndoState = true;
      isDrawing = true;
      isErasing = true;  // This is critical for erasing from chunks
    } else {
      // Other drawing modes (IMAGE, etc)
      captureUndoState = true;
      isDrawing = true;
      isErasing = false;
    }
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
  // Don't process mouse during startup screen
  if (showStartupScreen) return;
  
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
    if (currentPenMode == PEN_MODE_DEFAULT && lineCanvas != null) {
      // If we were drawing but didn't drag (single click), ensure we have at least one point
      if (isDrawing && prevMouse.x >= 0 && prevMouse.y >= 0) {
        // The point was already added in mousePressed, just end the stroke
        lineCanvas.endStroke();
      } else if (isDrawing) {
        // Add a single point if we clicked without dragging
        float canvasX, canvasY;
        if (isZoomed) {
          canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
          canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
        } else {
          canvasX = mouseX / displayScale;
          canvasY = mouseY / displayScale + scrollY;
        }
        // The point should already be there from startStroke, just end it
        lineCanvas.endStroke();
      }
    }
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
  // Don't process mouse during startup screen
  if (showStartupScreen) return;
  
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
  // Handle startup screen
  if (showStartupScreen) {
    if (key == ENTER || key == RETURN) {
      showStartupScreen = false;
      println("Starting paint application...");
    }
    return;  // Don't process other keys during startup
  }
  
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
    if (key == 's' || key == 'S') {
      // Cmd+S - Defer export to draw thread
      pendingExportDialog = true;
      return;
    } else if (key == 'z' || key == 'Z') {
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
  println("=== SAVE AND PRINT ===");
  
  // Check if we have anything to save
  boolean hasChunks = !chunkTextures.isEmpty();
  boolean hasLines = (lineCanvas != null && !lineCanvas.lines.isEmpty());
  
  if (!hasChunks && !hasLines) {
    println("Nothing to save");
    return;
  }
  
  // Find bounds
  int minY = Integer.MAX_VALUE;
  int maxY = Integer.MIN_VALUE;
  
  // Check chunk bounds
  if (hasChunks) {
    for (int i = 0; i < chunkPositions.size(); i++) {
      int chunkY = chunkPositions.get(i);
      minY = min(minY, chunkY);
      maxY = max(maxY, chunkY + CHUNK_HEIGHT);
    }
  }
  
  // Check line canvas bounds
  if (hasLines) {
    minY = min(minY, (int)lineCanvas.getMinY());
    maxY = max(maxY, (int)lineCanvas.getMaxY());
  }
  
  // Default to screen height if no content
  if (minY == Integer.MAX_VALUE) {
    minY = 0;
    maxY = SCREEN_HEIGHT;
  }
  
  println("Saving from Y=" + minY + " to Y=" + maxY);
  
  // Just grab the actual screen pixels - if it displays correctly, use that!
  // Get the current screen content
  PImage screenCapture = get(0, 0, width, height);
  
  // The screen shows scaled content, so we need to extract the lowRes portion
  // Actually, just grab directly from the main window at the correct size
  PImage finalImage = createImage(CANVAS_WIDTH, maxY - minY, RGB);
  finalImage.loadPixels();
  
  // Save current scroll
  float savedScrollY = scrollY;
  
  // For each section of the canvas, render and capture directly
  for (int y = minY; y < maxY; y += SCREEN_HEIGHT) {
    // Render this section directly to lowResCanvas (no scroll change needed)
    lowResCanvas.beginDraw();
    lowResCanvas.background(255);
    
    // Calculate what chunks are visible at this scroll position
    int startChunkY = max(0, (int)(y / CHUNK_HEIGHT) * CHUNK_HEIGHT);
    int endChunkY = (int)((y + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;
    
    // Render visible chunks
    for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
      for (int i = 0; i < chunkPositions.size(); i++) {
        if (chunkPositions.get(i) == chunkY) {
          PGraphics chunk = chunkTextures.get(i);
          float renderY = chunkY - y;  // Position relative to this section
          lowResCanvas.image(chunk, 0, renderY);
          break;
        }
      }
    }
    
    // Draw line canvas for this section
    if (lineCanvas != null) {
      lineCanvas.scrollTo(y);
      lineCanvas.update(); // Update with scroll position
      lineCanvas.draw(lowResCanvas, false, 1.0, 0, 0);
    }
    
    // Draw animations for this section
    if (animatedPen != null) {
      animatedPen.draw(lowResCanvas, y, false, 1.0, 0, 0);
    }
    
    lowResCanvas.endDraw();
    
    // Get the rendered section
    int sectionHeight = min(SCREEN_HEIGHT, maxY - y);
    PImage section = lowResCanvas.get(0, 0, CANVAS_WIDTH, sectionHeight);
    
    // Copy to final image at the correct position
    section.loadPixels();
    for (int py = 0; py < section.height; py++) {
      for (int px = 0; px < section.width; px++) {
        int srcIdx = py * section.width + px;
        int dstIdx = (y - minY + py) * CANVAS_WIDTH + px;
        if (dstIdx < finalImage.pixels.length && srcIdx < section.pixels.length) {
          finalImage.pixels[dstIdx] = section.pixels[srcIdx];
        }
      }
    }
  }
  
  finalImage.updatePixels();
  
  // Restore scroll
  scrollY = savedScrollY;
  
  // Save main output file
  String filename = "output.png";
  finalImage.save(filename);
  println("Saved: " + filename + " (" + CANVAS_WIDTH + "x" + (maxY-minY) + ")");
  
  // Also save timestamped copy
  String timestampedFilename = "glsl_paint_" + millis() + ".png";
  finalImage.save(timestampedFilename);
  
  // Show save confirmation modal
  showModal("SAVED: " + filename, 2000);
  
  // Print to thermal printer if requested
  if (printToReceipt) {
    printToThermalPrinter(filename);
  }
}

// Render the entire canvas (chunks + lines + animations) into a single PImage safely from draw()
PImage renderFullCanvasToImage() {
  int minY = 0;
  int maxY = (int)getMaxContentY();
  if (maxY <= minY) {
    return null;
  }

  PImage finalImage = createImage(CANVAS_WIDTH, maxY - minY, RGB);
  finalImage.loadPixels();

  float savedScrollY = scrollY;

  for (int y = minY; y < maxY; y += SCREEN_HEIGHT) {
    // Render this section directly to lowResCanvas
    lowResCanvas.beginDraw();
    lowResCanvas.background(255);

    int startChunkY = max(0, (int)(y / CHUNK_HEIGHT) * CHUNK_HEIGHT);
    int endChunkY = (int)((y + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;

    // Render visible chunks
    for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
      for (int i = 0; i < chunkPositions.size(); i++) {
        if (chunkPositions.get(i) == chunkY) {
          PGraphics chunk = chunkTextures.get(i);
          float renderY = chunkY - y;
          lowResCanvas.image(chunk, 0, renderY);
          break;
        }
      }
    }

    // Draw line canvas for this section
    if (lineCanvas != null) {
      lineCanvas.scrollTo(y);
      lineCanvas.update();
      lineCanvas.draw(lowResCanvas, false, 1.0, 0, 0);
    }

    // Draw animations for this section
    if (animatedPen != null) {
      animatedPen.draw(lowResCanvas, y, false, 1.0, 0, 0);
    }

    lowResCanvas.endDraw();

    int sectionHeight = min(SCREEN_HEIGHT, maxY - y);
    PImage section = lowResCanvas.get(0, 0, CANVAS_WIDTH, sectionHeight);

    section.loadPixels();
    for (int py = 0; py < section.height; py++) {
      for (int px = 0; px < section.width; px++) {
        int srcIdx = py * section.width + px;
        int dstIdx = (y - minY + py) * CANVAS_WIDTH + px;
        if (dstIdx < finalImage.pixels.length && srcIdx < section.pixels.length) {
          finalImage.pixels[dstIdx] = section.pixels[srcIdx];
        }
      }
    }
  }

  finalImage.updatePixels();
  scrollY = savedScrollY;
  return finalImage;
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
          // Map MIDI value (0-127) to pen mode (0-3)
          // 0-31: Default pen, 32-63: Remove pen, 64-95: Image pen, 96-127: Animation pen
          int newPenMode;
          if (value < 32) {
            newPenMode = PEN_MODE_DEFAULT;
          } else if (value < 64) {
            newPenMode = PEN_MODE_REMOVE;
          } else if (value < 96) {
            newPenMode = PEN_MODE_IMAGE;
          } else {
            newPenMode = PEN_MODE_ANIMATION;
          }
          
          // Set pending pen mode (thread-safe)
          pendingPenMode = newPenMode;
          
          // Visual feedback
          println("MIDI CC1: value=" + value + " → Pen mode = " + penModeNames[newPenMode]);
        }
        
        // Handle CC2 for color/image/animation selection
        if (ccNumber == 2) {
          if (currentPenMode == PEN_MODE_IMAGE) {
            // In image mode, CC2 selects the image
            // Map MIDI value (0-127) to image index (0-1)
            // 0-63: smile.png, 64-127: kit.gif
            int newImageIndex = value < 64 ? 0 : 1;
            
            // Set pending image index (thread-safe)
            pendingImageIndex = newImageIndex;
            
            // Visual feedback
            println("MIDI CC2: value=" + value + " → Image = " + stampImageNames[newImageIndex]);
          } else if (currentPenMode == PEN_MODE_ANIMATION) {
            // In animation mode, CC2 selects animation type
            // Currently only have cloud, but prepare for future
            // For now just show the animation type
            println("MIDI CC2: value=" + value + " → Animation = CLOUD (only type available)");
            // Will use this later when we have more animations:
            // animatedPen.currentAnimationType = value * animatedPen.animationTypeNames.length / 128;
            showAnimationTypeModal();
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
        
        // Handle CC3 for brush/image/animation size
        if (ccNumber == 3) {
          if (currentPenMode == PEN_MODE_IMAGE) {
            // In image mode, CC3 controls image size (10-128px)
            float newImageSize = map(value, 0, 127, 10, 128);
            newImageSize = constrain(newImageSize, 10, 128);
            
            // Set pending image size (thread-safe)
            pendingImageSize = newImageSize;
            
            // Visual feedback
            println("MIDI CC3: value=" + value + " → Image size = " + (int)newImageSize + "px");
          } else if (currentPenMode == PEN_MODE_ANIMATION) {
            // In animation mode, CC3 controls animation size (10-100px)
            float newAnimSize = map(value, 0, 127, 10, 100);
            newAnimSize = constrain(newAnimSize, 10, 100);
            
            // Set animation size directly (no pending needed since it's a simple variable)
            animationSize = newAnimSize;
            showAnimationSizeModal();
            
            // Visual feedback
            println("MIDI CC3: value=" + value + " → Animation size = " + (int)newAnimSize + "px");
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
        
        // Handle CC4 for animation control (line speed in DEFAULT, cloud density in ANIMATION)
        if (ccNumber == 4) {
          if (currentPenMode == PEN_MODE_DEFAULT) {
            // Control line animation speed in DEFAULT mode
            float newAnimSpeed = value / 127.0;  // 0 = stopped, 127 = full speed
            newAnimSpeed = constrain(newAnimSpeed, 0, 1.0);
            
            // Set pending animation speed (thread-safe)
            pendingAnimationSpeed = newAnimSpeed;
            
            // Visual feedback
            int speedPercent = (int)(newAnimSpeed * 100);
            println("MIDI CC4: value=" + value + " → Line animation speed = " + speedPercent + "%");
          } else if (currentPenMode == PEN_MODE_ANIMATION) {
            // Control cloud density in ANIMATION mode
            float newCloudDensity = value / 127.0;  // 0 = minimal clouds, 127 = maximum clouds
            newCloudDensity = constrain(newCloudDensity, 0, 1.0);
            
            // Set cloud density directly
            if (animatedPen != null) {
              animatedPen.setCloudDensity(newCloudDensity);
            }
            
            // Show modal
            pendingAnimationSpeed = -3;  // Special value for cloud density modal
            pendingCloudDensity = newCloudDensity;  // Store for modal display
            
            // Visual feedback
            int densityPercent = (int)(newCloudDensity * 100);
            println("MIDI CC4: value=" + value + " → Cloud density = " + densityPercent + "%");
          } else {
            // Show disabled modal for REMOVE and IMAGE modes
            pendingAnimationSpeed = -2;  // Special value to indicate disabled
            
            // Visual feedback
            String modeName = "";
            if (currentPenMode == PEN_MODE_REMOVE) {
              modeName = "REMOVE";
            } else if (currentPenMode == PEN_MODE_IMAGE) {
              modeName = "IMAGE";
            }
            println("MIDI CC4: value=" + value + " → CC4 DISABLED in " + modeName + " mode");
          }
        }
      }
    }
  }
  
  public void close() {
    // Cleanup if needed
  }
}

// Draw startup screen
void drawStartupScreen() {
  // Update animation time (for subtle blink)
  startupAnimTime += 0.016;

  // White background
  background(255);

  // Split screen into two equal halves
  float leftPanelWidth = width * 0.5;
  float rightPanelStart = leftPanelWidth;
  float rightPanelWidth = width - leftPanelWidth; // also 0.5 * width
  float centerY = height * 0.5;

  // Divider line between halves
  stroke(200);
  strokeWeight(1);
  line(leftPanelWidth, 0, leftPanelWidth, height);

  // === LEFT HALF: smile.png + "Press ENTER to start" (centered as a group) ===
  float maxImg = min(leftPanelWidth, height) * 0.48; // a bit smaller to fit text
  float imgW = maxImg;
  float imgH = maxImg;

  // Compute text size and height
  float txtSize = max(18, min(width, height) * 0.04);
  textSize(txtSize);
  float textH = textAscent() + textDescent();
  float gap = 24; // space between image and text

  // Total group height for vertical centering
  float groupH = imgH + gap + textH;
  float groupTopY = centerY - groupH * 0.5;

  // Draw image centered in left half
  if (stampImages != null && stampImages.length > 0 && stampImages[0] != null) {
    imageMode(CENTER);
    noSmooth();
    image(stampImages[0], leftPanelWidth * 0.5, groupTopY + imgH * 0.5, imgW, imgH);
    imageMode(CORNER);
  }

  // Draw ENTER prompt centered under the image (with gentle blink)
  textAlign(CENTER, CENTER);
  float blinkAlpha = (sin(startupAnimTime * 4) * 0.5 + 0.5) * 255;
  fill(0, blinkAlpha);
  text("Press ENTER to start", leftPanelWidth * 0.5, groupTopY + imgH + gap + textH * 0.5);

  // === RIGHT HALF: Controls & Features (centered block) ===
  float rightCenterX = rightPanelStart + rightPanelWidth * 0.5;
  float lineHeight = 22;
  float sectionSpacing = 35;

  // Measure total content height for vertical centering
  int drawingLines = 6; // list items in DRAWING section
  int systemLines = 5;  // list items in SYSTEM section
  int midiLines = midiConnected ? 4 : 0;
  int canvasInfoLines = 3; // Width/Height/Chunk
  boolean hasStampsInfo = (stampImages != null && stampImageNames != null && stampImageNames.length > 0);
  int extraInfoLines = (hasStampsInfo ? 1 : 0) + 1; // Stamps + MIDI status

  float totalH = 0;
  totalH += 40; // Title block
  totalH += lineHeight /* DRAWING header */ + drawingLines * lineHeight + sectionSpacing;
  totalH += lineHeight /* SYSTEM header */ + systemLines * lineHeight + sectionSpacing;
  if (midiConnected) {
    totalH += lineHeight /* MIDI header */ + midiLines * lineHeight + sectionSpacing;
  }
  totalH += lineHeight /* CANVAS INFO header */ + (canvasInfoLines + extraInfoLines) * lineHeight;

  float currentY = centerY - totalH * 0.5;

  // Title
  textSize(24);
  fill(0);
  textAlign(CENTER, TOP);
  text("CONTROLS & FEATURES", rightCenterX, currentY);
  currentY += 40;

  // DRAWING
  textSize(16);
  fill(0);
  text("DRAWING", rightCenterX, currentY);
  currentY += lineHeight;

  textSize(13);
  fill(60);
  text("Left Click — Draw / Stamp / Animate", rightCenterX, currentY); currentY += lineHeight;
  text("Right Click — No action", rightCenterX, currentY); currentY += lineHeight;
  text("Mouse Wheel — Scroll Canvas", rightCenterX, currentY); currentY += lineHeight;
  text("Arrow Keys — Scroll Canvas", rightCenterX, currentY); currentY += lineHeight;
  text("Space — Zoom Mode", rightCenterX, currentY); currentY += lineHeight;
  text("Tab (hold) — Debug Info", rightCenterX, currentY); currentY += sectionSpacing;

  // SYSTEM
  textSize(16);
  fill(0);
  text("SYSTEM", rightCenterX, currentY);
  currentY += lineHeight;

  textSize(13);
  fill(60);
  text("Cmd + S — Export PNG", rightCenterX, currentY); currentY += lineHeight;
  text("Cmd + Z — Undo", rightCenterX, currentY); currentY += lineHeight;
  text("Cmd + Shift + Z — Redo", rightCenterX, currentY); currentY += lineHeight;
  text("P — Save & Print", rightCenterX, currentY); currentY += lineHeight;
  text("ESC — Exit Application", rightCenterX, currentY); currentY += sectionSpacing;

  // MIDI (conditional)
  if (midiConnected) {
    textSize(16);
    fill(0);
    text("MIDI CONTROLS", rightCenterX, currentY);
    currentY += lineHeight;

    textSize(13);
    fill(60);
    text("CC1 — Pen Mode", rightCenterX, currentY); currentY += lineHeight;
    text("CC2 — Color / Image / Anim Type", rightCenterX, currentY); currentY += lineHeight;
    text("CC3 — Brush / Image / Anim Size", rightCenterX, currentY); currentY += lineHeight;
    text("CC4 — Line Speed / Cloud Density", rightCenterX, currentY); currentY += sectionSpacing;
  }

  // CANVAS INFO
  textSize(16);
  fill(0);
  text("CANVAS INFO", rightCenterX, currentY);
  currentY += lineHeight;

  textSize(13);
  fill(60);
  text("Width — " + CANVAS_WIDTH + " px", rightCenterX, currentY); currentY += lineHeight;
  text("Height — Infinite scroll", rightCenterX, currentY); currentY += lineHeight;
  text("Chunk Size — " + CHUNK_HEIGHT + " px", rightCenterX, currentY); currentY += lineHeight;
  if (hasStampsInfo) { text("Stamps — " + stampImageNames.length + " loaded", rightCenterX, currentY); currentY += lineHeight; }
  text("MIDI — " + (midiConnected ? "Connected" : "Not Connected"), rightCenterX, currentY);

  // Reset alignment
  textAlign(LEFT, TOP);
}

// Update animated GIF frames
void updateGifAnimations() {
  int currentTime = millis();
  
  // Check if it's time to update frames
  if (currentTime - lastFrameUpdate > frameUpdateInterval) {
    for (int i = 0; i < stampImageNames.length; i++) {
      if (isAnimated[i] && gifFrames[i] != null && totalFrames[i] > 0) {
        // Advance to next frame
        currentFrameIndex[i] = (currentFrameIndex[i] + 1) % totalFrames[i];
        stampImages[i] = gifFrames[i][currentFrameIndex[i]];
      }
    }
    lastFrameUpdate = currentTime;
  }
}

// Helper function to draw image with transparency
void drawImageWithTransparency(PGraphics canvas, PImage img, float x, float y, float size, int alpha) {
  // Draw the image with its native transparency
  canvas.noSmooth();  // Disable interpolation for sharp pixels
  canvas.tint(255, alpha);  // Apply alpha tint
  canvas.imageMode(CENTER);
  canvas.image(img, x, y, size, size);
  canvas.imageMode(CORNER);
  canvas.noTint();  // Reset tint
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

// Export canvas as PNG with file dialog
void exportPNGWithDialog() {
  // Request export via draw() thread
  pendingExportDialog = true;
}

// Callback for file save dialog
void saveCanvasCallback(File selection) {
  if (selection == null) {
    showModal("EXPORT CANCELLED", 1000);
    // Clear any previously cached export image
    cachedExportImage = null;
    return;
  }
  
  // Ensure filename ends with .png
  String filename = selection.getAbsolutePath();
  if (!filename.toLowerCase().endsWith(".png")) {
    filename += ".png";
  }
  
  // Save the cached image produced on the draw thread
  if (cachedExportImage == null) {
    // Fallback: try rendering now (may be less safe but better than failing silently)
    cachedExportImage = renderFullCanvasToImage();
  }
  if (cachedExportImage != null) {
    cachedExportImage.save(filename);
  } else {
    showModal("NO CONTENT TO SAVE", 1500);
    return;
  }
  // Clear cache now that we've saved it
  cachedExportImage = null;
  
  // Get just the filename for display
  String displayName = new File(filename).getName();
  showModal("EXPORTED: " + displayName, 2000);
  println("Exported canvas to: " + filename);
}

// Removed all slot-related functions - now using simple PNG export

/* OLD SLOT FUNCTIONS REMOVED:
 * checkSaveSlots()
 * drawSlotSelectionScreen() 
 * updateSlotHover()
 * handleSlotClick()
 * deleteSlotData()
 * saveToSlot()
 * loadFromSlot()
 */
