



import java.io.*;
import java.util.HashMap;
import processing.data.IntList;
import javax.sound.midi.*;

ArrayList<PGraphics> chunkTextures;  
ArrayList<Integer> chunkPositions;
HashMap<Integer, Integer> chunkIndexMap;  


LineCanvas lineCanvas;


final int CANVAS_WIDTH = 320;
final int CHUNK_HEIGHT = 128;  
int SCREEN_HEIGHT = 180;  
final int MAX_CHUNKS = 50;  


final float BASE_FRAME_RATE = 60.0f;
final float TARGET_FRAME_RATE = 120.0f;
final float MAX_DELTA_SECONDS = 1.0f / 15.0f;
float deltaSeconds = 1.0f / BASE_FRAME_RATE;
float frameTimeScale = 1.0f;
int lastFrameMillis = -1;


boolean isDrawing = false;
boolean isErasing = false;
float brushSize = 2.0;  
float scrollY = 0;
boolean pendingSave = false;  
boolean pendingPrint = false;  

boolean pendingExportDialog = false;  
PImage cachedExportImage = null;      
boolean showDebugInfo = false;  


int PEN_MODE_DEFAULT = 0;
int PEN_MODE_REMOVE = 1;
int PEN_MODE_IMAGE = 2;
int PEN_MODE_ANIMATION = 3;
int currentPenMode = PEN_MODE_DEFAULT;
String[] penModeNames = {"DEFAULT", "REMOVE", "IMAGE", "ANIMATION"};


int currentColorIndex = 0;  
String[] colorNames = {
  "#94A1FF",
  "#6ED4E3",
  "#D4F357",
  "#FFA020",
  "#BEC5BD",
  "BLACK",
  "GREEN",
  "RAINBOW"
};
color[] palette = new color[colorNames.length];


int[][] rainbowDitherMatrix;
int[][] rainbowFadeDitherMatrix;
color[] rainbowPalette;
final int RAINBOW_BLOCK_SIZE = 6;
final color RAINBOW_HIGHLIGHT_COLOR = 0xFFFFFFFF;
final float RAINBOW_FADE_HEIGHT = 150.0f;
final int RAINBOW_FADE_SUBCELL_SIZE = 1;


String modalMessage = "";
int modalStartTime = 0;
int modalDuration = 1000;  
boolean modalVisible = false;
boolean modalPersistent = false;  
boolean modalShowColorPalette = false;  
boolean modalShowBrush = false;  
boolean modalShowPenMode = false;  
boolean modalShowImagePreview = false;  


boolean isSelectingZoom = false;  
boolean isZoomed = false;  
PVector zoomSelectionStart = new PVector(-1, -1);
PVector zoomSelectionEnd = new PVector(-1, -1);
float zoomScale = 1.0;
float zoomOffsetX = 0;
float zoomOffsetY = 0;

PVector prevMouse = new PVector(-1, -1);


ArrayList<PGraphics> undoChunkTextures;  
ArrayList<PGraphics> redoChunkTextures;  
boolean hasUndo = false;
boolean hasRedo = false;
boolean captureUndoState = false;  
String[] undoLineState = null;
String[] redoLineState = null;
String[] undoAnimationState = null;
String[] redoAnimationState = null;
boolean pendingUndo = false;  
boolean pendingRedo = false;  


PGraphics lowResCanvas;
float displayScale = 1.0;


boolean showStartupScreen = true;  
float startupAnimTime = 0;


MidiDevice midiDevice = null;
boolean midiConnected = false;
volatile float pendingBrushSize = -1;  
volatile int pendingColorIndex = -1;  
volatile int pendingPenMode = -1;  
volatile int pendingImageIndex = -1;  
volatile float pendingImageSize = -1;  
volatile float pendingAnimationSpeed = -1;  
volatile float pendingAnimationParamValue = -1;  
volatile String pendingAnimationParamLabel = "";  
int lastMidiCheck = 0;
float lastKnownBrushSize = 2.0;  


PImage[] stampImages;
String[] stampImageNames = {"smile.png", "kit.gif"};
int currentImageIndex = 0;
float imageStampSize = 32.0;  
boolean modalShowImageSelect = false;  


PImage[][] gifFrames;  
int[] currentFrameIndex;  
int[] totalFrames;  
int frameUpdateInterval = 38;  
int lastFrameUpdate = 0;
boolean[] isAnimated;  


AnimatedPen animatedPen;
float animationSize = 20.0;  
boolean modalShowAnimationType = false;  
boolean modalShowAnimationSelect = false;  

void setup() {
  fullScreen(JAVA2D);  
  pixelDensity(1);  
  noSmooth();  

  
  displayScale = (float)width / CANVAS_WIDTH;
  
  
  SCREEN_HEIGHT = (int)(height / displayScale);
  
  
  lowResCanvas = createGraphics(CANVAS_WIDTH, SCREEN_HEIGHT);
  lowResCanvas.noSmooth();  
  
  
  chunkTextures = new ArrayList<PGraphics>();
  chunkPositions = new ArrayList<Integer>();
  chunkIndexMap = new HashMap<Integer, Integer>();
  
  
  lineCanvas = new LineCanvas();
  
  
  undoChunkTextures = new ArrayList<PGraphics>();
  redoChunkTextures = new ArrayList<PGraphics>();
  
  
  palette[0] = color(0x94, 0xA1, 0xFF); 
  palette[1] = color(0x6E, 0xD4, 0xE3);
  palette[2] = color(0xD4, 0xF3, 0x57);
  palette[3] = color(0xFF, 0xA0, 0x20);
  palette[4] = color(0xBE, 0xC5, 0xBD);
  palette[5] = color(0, 0, 0);       
  palette[6] = color(0, 255, 0);     
  palette[7] = color(255, 0, 255);   // placeholder color for rainbow preview
  
  rainbowDitherMatrix = new int[][] {
    {0, 8, 2, 10},
    {12, 4, 14, 6},
    {3, 11, 1, 9},
    {15, 7, 13, 5}
  };
  rainbowFadeDitherMatrix = new int[][] {
    {0, 48, 12, 60, 3, 51, 15, 63},
    {32, 16, 44, 28, 35, 19, 47, 31},
    {8, 56, 4, 52, 11, 59, 7, 55},
    {40, 24, 36, 20, 43, 27, 39, 23},
    {2, 50, 14, 62, 1, 49, 13, 61},
    {34, 18, 46, 30, 33, 17, 45, 29},
    {10, 58, 6, 54, 9, 57, 5, 53},
    {42, 26, 38, 22, 41, 25, 37, 21}
  };
  IntList rainbowColors = new IntList();
  for (int i = 0; i < palette.length; i++) {
    if (i == 5 || i == 7) {
      continue; // skip black and placeholder magenta for rainbow background
    }
    rainbowColors.append(palette[i]);
  }
  if (rainbowColors.size() == 0) {
    rainbowColors.append(color(255));
  }
  rainbowPalette = new color[rainbowColors.size()];
  for (int i = 0; i < rainbowColors.size(); i++) {
    rainbowPalette[i] = rainbowColors.get(i);
  }
  
  
  createChunk(0);
  
  
  initMIDI();
  
  
  frameRate(TARGET_FRAME_RATE);
  
  
  animatedPen = new AnimatedPen();
  
  println("CPU-based infinite canvas initialized");
  println("Canvas width: " + CANVAS_WIDTH + "px");
  println("CPU chunk rendering enabled");
  println("Max chunks: " + MAX_CHUNKS);
  
  stampImages = new PImage[stampImageNames.length];
  gifFrames = new PImage[stampImageNames.length][];
  currentFrameIndex = new int[stampImageNames.length];
  totalFrames = new int[stampImageNames.length];
  isAnimated = new boolean[stampImageNames.length];
  
  for (int i = 0; i < stampImageNames.length; i++) {
    String fileName = stampImageNames[i];
    
    if (fileName.equals("kit.gif")) {
      
      ArrayList<PImage> frameList = new ArrayList<PImage>();
      int frameNum = 1;
      
      
      
      
      boolean skipTwo = true;
      while (frameNum <= 400) {
        String framePath = String.format("kit_frames/kit_frame_%02d.png", frameNum);
        PImage frame = loadImage(framePath);
        if (frame != null) {
          frameList.add(frame);
        } else {
          break;  
        }
        
        frameNum += skipTwo ? 2 : 3;
        skipTwo = !skipTwo;
      }
      
      if (frameList.size() > 0) {
        gifFrames[i] = frameList.toArray(new PImage[frameList.size()]);
        totalFrames[i] = gifFrames[i].length;
        stampImages[i] = gifFrames[i][0];  
        isAnimated[i] = true;
        currentFrameIndex[i] = 0;
        println("Loaded animated GIF: " + fileName + " with " + totalFrames[i] + " frames at 20fps");
      } else {
        
        stampImages[i] = loadImage(fileName);
        isAnimated[i] = false;
        totalFrames[i] = 1;
        println("Failed to load frames, using static: " + fileName);
      }
    } else {
      
      stampImages[i] = loadImage(fileName);
      if (stampImages[i] != null) {
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


void saveUndoState() {
  
  for (PGraphics g : undoChunkTextures) {
    if (g != null) g.dispose();
  }
  undoChunkTextures.clear();
  
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    undoChunkTextures.add(copy);
  }
  
  if (lineCanvas != null) {
    undoLineState = lineCanvas.serializeState();
  } else {
    undoLineState = null;
  }
  if (animatedPen != null) {
    undoAnimationState = animatedPen.serializeState();
  } else {
    undoAnimationState = null;
  }

  hasUndo = true;
  hasRedo = false;  
  
  redoLineState = null;
  redoAnimationState = null;

  
  for (PGraphics g : redoChunkTextures) {
    if (g != null) g.dispose();
  }
  redoChunkTextures.clear();
}


void performUndo() {
  if (!hasUndo || undoChunkTextures.isEmpty()) return;
  
  
  for (PGraphics g : redoChunkTextures) {
    if (g != null) g.dispose();
  }
  redoChunkTextures.clear();
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    redoChunkTextures.add(copy);
  }

  if (lineCanvas != null) {
    redoLineState = lineCanvas.serializeState();
  } else {
    redoLineState = null;
  }
  if (animatedPen != null) {
    redoAnimationState = animatedPen.serializeState();
  } else {
    redoAnimationState = null;
  }
  
  
  for (int i = 0; i < min(chunkTextures.size(), undoChunkTextures.size()); i++) {
    PGraphics undoChunk = undoChunkTextures.get(i);
    PGraphics currentChunk = chunkTextures.get(i);
    currentChunk.beginDraw();
    currentChunk.image(undoChunk, 0, 0);
    currentChunk.endDraw();
  }

  if (lineCanvas != null) {
    if (undoLineState != null) {
      lineCanvas.deserializeState(undoLineState);
    } else {
      lineCanvas.clear();
    }
    lineCanvas.update(0);
  }

  if (animatedPen != null) {
    if (undoAnimationState != null) {
      animatedPen.deserializeState(undoAnimationState);
    } else {
      animatedPen.animations.clear();
    }
  }
  
  hasRedo = true;
  hasUndo = false;

  undoLineState = null;
  undoAnimationState = null;
}


void performRedo() {
  if (!hasRedo || redoChunkTextures.isEmpty()) return;
  
  
  for (PGraphics g : undoChunkTextures) {
    if (g != null) g.dispose();
  }
  undoChunkTextures.clear();
  
  for (PGraphics chunk : chunkTextures) {
    PGraphics copy = createGraphics(chunk.width, chunk.height);
    copy.noSmooth();
    copy.beginDraw();
    copy.image(chunk, 0, 0);
    copy.endDraw();
    undoChunkTextures.add(copy);
  }

  if (lineCanvas != null) {
    undoLineState = lineCanvas.serializeState();
  } else {
    undoLineState = null;
  }
  if (animatedPen != null) {
    undoAnimationState = animatedPen.serializeState();
  } else {
    undoAnimationState = null;
  }
  
  
  for (int i = 0; i < min(chunkTextures.size(), redoChunkTextures.size()); i++) {
    PGraphics redoChunk = redoChunkTextures.get(i);
    PGraphics currentChunk = chunkTextures.get(i);
    currentChunk.beginDraw();
    currentChunk.image(redoChunk, 0, 0);
    currentChunk.endDraw();
  }

  if (lineCanvas != null) {
    if (redoLineState != null) {
      lineCanvas.deserializeState(redoLineState);
    } else {
      lineCanvas.clear();
    }
    lineCanvas.update(0);
  }

  if (animatedPen != null) {
    if (redoAnimationState != null) {
      animatedPen.deserializeState(redoAnimationState);
    } else {
      animatedPen.animations.clear();
    }
  }
  
  hasUndo = true;
  hasRedo = false;

  redoLineState = null;
  redoAnimationState = null;
}

void createChunk(int yPos) {
  
  if (chunkIndexMap.containsKey(yPos)) {
    return;
  }
  
  
  if (chunkPositions.size() >= MAX_CHUNKS) {
    println("Chunk limit reached (" + MAX_CHUNKS + " chunks max)");
    return;
  }
  
  
  PGraphics chunk = createGraphics(CANVAS_WIDTH, CHUNK_HEIGHT);
  chunk.noSmooth();

  
  chunk.beginDraw();
  chunk.background(255, 255, 255);
  chunk.noStroke();
  chunk.fill(255);
  chunk.rect(0, 0, CANVAS_WIDTH, CHUNK_HEIGHT);
  chunk.endDraw();

  chunkTextures.add(chunk);
  chunkPositions.add(yPos);
  chunkIndexMap.put(yPos, chunkTextures.size() - 1);
}

int getChunkIndex(float globalY) {
  
  if (globalY < 0) return -1;
  
  int chunkY = ((int)globalY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
  
  
  createChunk(chunkY);
  
  
  Integer chunkIndex = chunkIndexMap.get(chunkY);
  return chunkIndex != null ? chunkIndex : -1;
}

void applyPaintToChunk(int chunkIndex, float globalMouseX, float globalMouseY,
                       float globalPrevX, float globalPrevY) {
  if (chunkIndex < 0) return;
  
  int chunkY = chunkPositions.get(chunkIndex);
  float localMouseY = globalMouseY - chunkY;
  float localPrevY = globalPrevY - chunkY;
  
  
  float effectRadius = (currentPenMode == PEN_MODE_IMAGE) ? imageStampSize * 0.5 : brushSize * 0.5;
  if (localMouseY < -effectRadius - 10 || localMouseY > CHUNK_HEIGHT + effectRadius + 10) {
    return;
  }
  
  

  PGraphics chunk = chunkTextures.get(chunkIndex);
  chunk.beginDraw();

  if (currentPenMode == PEN_MODE_IMAGE) {
    if (stampImages != null && currentImageIndex < stampImages.length && stampImages[currentImageIndex] != null) {
      chunk.imageMode(CENTER);
      chunk.image(stampImages[currentImageIndex], globalMouseX, localMouseY, imageStampSize, imageStampSize);
      chunk.imageMode(CORNER);
    }
  } else {
    color drawColor = palette[currentColorIndex];
    if (isErasing) {
      chunk.stroke(255);
      chunk.fill(255);
    } else {
      chunk.stroke(drawColor);
      chunk.fill(drawColor);
    }

    float effectiveBrushSize = isErasing ? brushSize * 5.0 : brushSize;
    chunk.strokeWeight(effectiveBrushSize);
    chunk.strokeCap(ROUND);

    if (globalPrevX >= 0 && globalPrevY >= 0) {
      chunk.line(globalPrevX, localPrevY, globalMouseX, localMouseY);
    }

    chunk.noStroke();
    chunk.ellipse(globalMouseX, localMouseY, effectiveBrushSize, effectiveBrushSize);
  }

  chunk.endDraw();
}

void draw() {
  int now = millis();
  if (lastFrameMillis < 0) {
    deltaSeconds = 1.0f / BASE_FRAME_RATE;
  } else {
    deltaSeconds = (now - lastFrameMillis) / 1000.0f;
  }
  lastFrameMillis = now;
  deltaSeconds = constrain(deltaSeconds, 0, MAX_DELTA_SECONDS);
  frameTimeScale = deltaSeconds * BASE_FRAME_RATE;
  
  updateGifAnimations();
  
  
  if (animatedPen != null) {
    animatedPen.update(deltaSeconds, frameTimeScale);
  }
  
  
  if (showStartupScreen) {
    drawStartupScreen();
    return;
  }
  
  
  if (pendingUndo) {
    performUndo();
    pendingUndo = false;
  }
  if (pendingRedo) {
    performRedo();
    pendingRedo = false;
  }
  
  
  if (pendingBrushSize > 0) {
    brushSize = pendingBrushSize;
    pendingBrushSize = -1;
    showBrushModal();  
  }
  
  if (pendingImageSize > 0) {
    imageStampSize = pendingImageSize;
    pendingImageSize = -1;
    showImageSizeModal();  
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
      int paramPercent = (int)(pendingAnimationParamValue * 100);
      String label = (pendingAnimationParamLabel != null && pendingAnimationParamLabel.length() > 0)
        ? pendingAnimationParamLabel.toUpperCase()
        : "ANIM PARAM";
      showModal(label + ": " + paramPercent + "%", 1000);
      pendingAnimationSpeed = -1;
      pendingAnimationParamValue = -1;
      pendingAnimationParamLabel = "";
    } else if (pendingAnimationSpeed == -2) {
      
      showModal("CC4: ✗ DISABLED", 1000);
      pendingAnimationSpeed = -1;
    } else if (pendingAnimationSpeed >= 0) {
      if (lineCanvas != null) {
        lineCanvas.setAnimationIntensity(pendingAnimationSpeed);
      }
      pendingAnimationSpeed = -1;
      
      int speedPercent = (int)(lineCanvas.animationIntensity * 100);
      showModal("LINE ANIM: " + speedPercent + "%", 1000);
    }
  }
  
  
  if (lineCanvas != null) {
    lineCanvas.update(frameTimeScale);
    lineCanvas.scrollTo(scrollY);
  }
  
  
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  maxScroll = max(0, maxScroll);
  scrollY = constrain(scrollY, 0, maxScroll);
  
  
  if ((isDrawing || isErasing) && !isSelectingZoom) {
    
    if (currentPenMode == PEN_MODE_REMOVE) {
      
      
      float globalMouseX, globalMouseY;
      
      if (isZoomed) {
        globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        globalMouseX = mouseX / displayScale;
        globalMouseY = mouseY / displayScale + scrollY;
      }
      
      
      float eraserRadius = brushSize * 5;  
      if (lineCanvas != null) {
        lineCanvas.eraseAt(globalMouseX, globalMouseY, eraserRadius);
      }
      
      
      if (animatedPen != null) {
        
        animatedPen.eraseAt(globalMouseX, globalMouseY, eraserRadius);
      }
      
    }
    
    
    if (currentPenMode == PEN_MODE_ANIMATION) {
      
      
    } else if (currentPenMode == PEN_MODE_DEFAULT && lineCanvas != null) {
      
      
      float globalMouseX, globalMouseY;
      
      if (isZoomed) {
        globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        globalMouseX = mouseX / displayScale;
        globalMouseY = mouseY / displayScale + scrollY;
      }
      
      
      int chunkY = ((int)globalMouseY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
      createChunk(chunkY);
      
      
      lineCanvas.addPoint(globalMouseX, globalMouseY);
      
      if (currentColorIndex == palette.length - 1) {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], true);
      } else {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], false);
      }
      lineCanvas.setWeight(brushSize);
      
      prevMouse.set(globalMouseX, globalMouseY);
    } else {
      
      if (captureUndoState) {
        saveUndoState();
        captureUndoState = false;
      }
      
      
      float globalMouseX, globalMouseY;
      
      if (isZoomed) {
        
        globalMouseX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        globalMouseY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        
        globalMouseX = mouseX / displayScale;
        globalMouseY = mouseY / displayScale + scrollY;
      }
      
      
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
    
    prevMouse.set(-1, -1);
  }
  
  
  lowResCanvas.beginDraw();
  lowResCanvas.background(255);  
  
  
  if (isZoomed) {
    lowResCanvas.pushMatrix();
    lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
    lowResCanvas.scale(zoomScale);
    lowResCanvas.noSmooth();  
  }
  
  
  int startChunkY = max(0, (int)(scrollY / CHUNK_HEIGHT) * CHUNK_HEIGHT);
  int endChunkY = (int)((scrollY + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;
  
  for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
    Integer chunkIdx = chunkIndexMap.get(chunkY);
    if (chunkIdx != null) {
      PGraphics chunk = chunkTextures.get(chunkIdx);
      float renderY = chunkY - scrollY;
      lowResCanvas.image(chunk, 0, renderY);
    } else {
      
      float renderY = chunkY - scrollY;
      if (renderY < SCREEN_HEIGHT && renderY + CHUNK_HEIGHT > 0) {
        drawRainbowSection(renderY, min(CHUNK_HEIGHT, SCREEN_HEIGHT - (int)renderY));
      }
    }
  }
  
  if (isZoomed) {
    lowResCanvas.popMatrix();
  }
  
  
  if (lineCanvas != null) {
    lineCanvas.draw(lowResCanvas, isZoomed, zoomScale, zoomOffsetX, zoomOffsetY);
  }
  
  
  if (animatedPen != null) {
    animatedPen.draw(lowResCanvas, scrollY, isZoomed, zoomScale, zoomOffsetX, zoomOffsetY);
    
    
    if (currentPenMode == PEN_MODE_REMOVE) {
      float lowResMouseX = mouseX / displayScale;
      float lowResMouseY = mouseY / displayScale;
      
      
      float canvasMouseX, canvasMouseY;
      if (isZoomed) {
        canvasMouseX = (lowResMouseX - zoomOffsetX) / zoomScale;
        canvasMouseY = (lowResMouseY - zoomOffsetY) / zoomScale + scrollY;
      } else {
        canvasMouseX = lowResMouseX;
        canvasMouseY = lowResMouseY + scrollY;
      }
      
      
      for (AnimationInstance anim : animatedPen.animations) {
        float dist = dist(canvasMouseX, canvasMouseY, anim.originX, anim.originY);
        boolean isNear = dist < 50;  
        
        
        lowResCanvas.pushStyle();
        
        if (isZoomed) {
          lowResCanvas.pushMatrix();
          lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
          lowResCanvas.scale(zoomScale);
        }
        
        float rectX = anim.originX;
        float rectY = anim.originY - scrollY;
        float rectSize = 20;
        
        
        if (isNear) {
          
          lowResCanvas.fill(255, 100, 0, 80);  
          lowResCanvas.stroke(255, 100, 0, 200);  
        } else {
          
          lowResCanvas.fill(255, 100, 0, 30);  
          lowResCanvas.stroke(255, 100, 0, 100);  
        }
        lowResCanvas.strokeWeight(2);
        lowResCanvas.rectMode(CENTER);
        lowResCanvas.rect(rectX, rectY, rectSize, rectSize, 3);  
        
        
        lowResCanvas.stroke(255, 255, 255, isNear ? 255 : 150);  
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
  
  
  drawLowResUI();
  
  
  if (isSelectingZoom && zoomSelectionStart.x >= 0) {
    
    float time = millis() * 0.001;  
    color[] happyColors = {
      color(255, 255, 85),  
      color(85, 255, 255),  
      color(255, 85, 255),  
      color(85, 255, 85),   
      color(255, 170, 85),  
      color(255, 85, 170),  
      color(170, 255, 85),  
      color(85, 255, 170),  
      color(255, 255, 170), 
      color(170, 255, 255), 
      color(255, 170, 255), 
      color(170, 170, 255)  
    };
    
    float x1 = min(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y1 = min(zoomSelectionStart.y, zoomSelectionEnd.y);
    float x2 = max(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y2 = max(zoomSelectionStart.y, zoomSelectionEnd.y);
    
    
    int colorIndex = (int)(time * 10) % happyColors.length;
    
    lowResCanvas.noFill();
    lowResCanvas.stroke(happyColors[colorIndex]);
    lowResCanvas.strokeWeight(3);  
    lowResCanvas.rect(x1, y1, x2 - x1, y2 - y1);
  }
  
  lowResCanvas.endDraw();
  
  
  background(0);
  
  pushMatrix();
  scale(displayScale);
  noSmooth();  
  image(lowResCanvas, 0, 0);
  popMatrix();
}

void drawRainbowSection(float yOffset, int height) {
  if (height <= 0) {
    return;
  }

  float time = millis() * 0.00005f;  
  int[][] ditherMatrix = rainbowDitherMatrix;
  color[] colors = rainbowPalette;
  int paletteSize = colors.length;
  int ditherRows = ditherMatrix.length;
  int ditherCols = ditherMatrix[0].length;
  float baseY = yOffset + scrollY;
  int[][] fadeMatrix = rainbowFadeDitherMatrix;
  int fadeRows = (fadeMatrix != null) ? fadeMatrix.length : 0;
  int fadeCols = (fadeMatrix != null && fadeMatrix.length > 0) ? fadeMatrix[0].length : 0;
  int fadeSteps = (fadeRows > 0 && fadeCols > 0) ? fadeRows * fadeCols : 0;
  int fadeCellSize = RAINBOW_FADE_SUBCELL_SIZE;
  if (fadeCellSize < 1 || fadeCellSize > RAINBOW_BLOCK_SIZE || (RAINBOW_BLOCK_SIZE % fadeCellSize) != 0) {
    fadeCellSize = 1;
  }
  boolean fadeEnabled = RAINBOW_FADE_HEIGHT > 0.0f && fadeSteps > 0;

  lowResCanvas.strokeWeight(1);
  lowResCanvas.noSmooth();

  for (int y = 0; y < height; y += RAINBOW_BLOCK_SIZE) {
    float globalY = baseY + y;
    int dy = ((int)(globalY / RAINBOW_BLOCK_SIZE)) % ditherRows;
    if (dy < 0) {
      dy += ditherRows;
    }

    float bandSeed = globalY * 0.01f + time * 100f;

    for (int x = 0; x < CANVAS_WIDTH; x += RAINBOW_BLOCK_SIZE) {
      int dx = (x / RAINBOW_BLOCK_SIZE) % ditherCols;
      float ditherValue = ditherMatrix[dy][dx] / 15.0f;

      int rawIndex = (int)(bandSeed + x * 0.01f + ditherValue * 4f);
      int colorIndex = rawIndex % paletteSize;
      if (colorIndex < 0) {
        colorIndex += paletteSize;
      }

      float drawY = yOffset + y;
      color c = colors[colorIndex];
      boolean handledFade = false;
      if (fadeEnabled && y < RAINBOW_FADE_HEIGHT) {
        lowResCanvas.noStroke();
        lowResCanvas.fill(c);

        for (int subY = 0; subY < RAINBOW_BLOCK_SIZE; subY += fadeCellSize) {
          float localY = y + subY + fadeCellSize * 0.5f;
          float fadeProgress = constrain(localY / RAINBOW_FADE_HEIGHT, 0.0f, 1.0f);
          if (fadeProgress <= 0.0f) {
            continue;
          }

          float fadeLevel = fadeProgress * fadeSteps;
          for (int subX = 0; subX < RAINBOW_BLOCK_SIZE; subX += fadeCellSize) {
            int sampleX = (int)floor((x + subX) / (float)fadeCellSize);
            int sampleY = (int)floor((drawY + subY) / (float)fadeCellSize);
            int fadeDy = sampleY % fadeRows;
            int fadeDx = sampleX % fadeCols;
            if (fadeDy < 0) {
              fadeDy += fadeRows;
            }
            if (fadeDx < 0) {
              fadeDx += fadeCols;
            }

            float threshold = fadeMatrix[fadeDy][fadeDx];
            if (fadeLevel <= threshold) {
              continue;
            }

            float cellX = x + subX;
            float cellY = drawY + subY;
            lowResCanvas.rect(cellX, cellY, fadeCellSize, fadeCellSize);
          }
        }

        handledFade = true;
      }

      if (!handledFade) {
        lowResCanvas.noStroke();
        lowResCanvas.fill(c);
        lowResCanvas.rect(x, drawY, RAINBOW_BLOCK_SIZE, RAINBOW_BLOCK_SIZE);

        if (ditherValue > 0.5) {
          color highlight = lerpColor(c, RAINBOW_HIGHLIGHT_COLOR, 0.2f);
          lowResCanvas.stroke(highlight);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(x, drawY + 2, x + RAINBOW_BLOCK_SIZE, drawY + 2);
          lowResCanvas.line(x, drawY + 6, x + RAINBOW_BLOCK_SIZE, drawY + 6);
          lowResCanvas.noStroke();
        }
      }
    }
  }
}


void showModal(String message, int duration) {
  modalMessage = message;
  modalStartTime = millis();
  modalDuration = duration;
  modalVisible = true;
  modalPersistent = false;
  modalShowColorPalette = false;
  modalShowBrush = false;  
  modalShowPenMode = false;  
  modalShowImagePreview = false;  
  modalShowAnimationSelect = false;  
}


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
  modalShowImageSelect = false;  
}


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


void showModal(String message) {
  showModal(message, 1000);
}


void showPersistentModal(String message) {
  modalMessage = message;
  modalVisible = true;
  modalPersistent = true;
  modalShowColorPalette = false;  
  modalShowBrush = false;  
  modalShowPenMode = false;  
  modalShowImagePreview = false;  
  modalShowAnimationSelect = false;  
}


void clearPersistentModal() {
  if (modalPersistent) {
    modalVisible = false;
    modalPersistent = false;
  }
}


void drawModal() {
  if (modalVisible) {
    
    if (!modalPersistent && millis() - modalStartTime > modalDuration) {
      modalVisible = false;
      return;
    }
    
    
    float opacity = 255;
    if (!modalPersistent) {
      int timeLeft = modalDuration - (millis() - modalStartTime);
      if (timeLeft < 200) {
        opacity = map(timeLeft, 0, 200, 0, 255);
      }
    }
    
    
    lowResCanvas.textSize(10);
    float padding = 8;
    float boxWidth, boxHeight;
    
    if (modalShowColorPalette) {
      int boxSize = 20;
      int boxSpacing = 30;
      int colorCount = colorNames.length;
      int cols = min(5, colorCount);
      int rows = (colorCount + cols - 1) / cols;
      int totalWidth = cols * boxSpacing - (boxSpacing - boxSize);
      int totalHeight = rows * boxSpacing - (boxSpacing - boxSize);
      boxWidth = max(180, totalWidth + padding * 2);
      boxHeight = totalHeight + padding * 2;
    } else if (modalShowBrush) {
      
      boxWidth = 80;  
      boxHeight = 24;  
    } else if (modalShowPenMode) {
      
      boxWidth = 130;  
      boxHeight = 30;  
    } else if (modalShowImagePreview) {
      
      boxWidth = stampImageNames.length * 30 + 10;  
      boxHeight = 40;  
    } else if (modalShowAnimationSelect) {
      int animCount = animatedPen.animationTypeNames.length;
      int cols = min(5, animCount);
      int rows = (animCount + cols - 1) / cols;
      boxWidth = cols * 30 + 10;
      boxHeight = rows * 30 + 20;
    } else {
      float textWidth = lowResCanvas.textWidth(modalMessage);
      boxWidth = textWidth + padding * 2;
      boxHeight = 20;  
    }
    
    
    float lowResMouseX = mouseX / displayScale;
    float lowResMouseY = mouseY / displayScale;
    boolean mouseInRightHalf = lowResMouseX > CANVAS_WIDTH / 2;
    boolean mouseInBottomHalf = lowResMouseY > SCREEN_HEIGHT / 2;

    float margin = 4;
    float leftX = margin;
    float rightX = max(margin, CANVAS_WIDTH - boxWidth - margin);
    float topY = margin;
    float bottomY = max(margin, SCREEN_HEIGHT - boxHeight - margin);

    float modalX = mouseInRightHalf ? leftX : rightX;
    float modalY = mouseInBottomHalf ? topY : bottomY;
    
    
    float time = millis() * 0.001;  
    color[] happyColors = {
      color(255, 255, 85),  
      color(85, 255, 255),  
      color(255, 85, 255),  
      color(85, 255, 85),   
      color(255, 170, 85),  
      color(255, 85, 170),  
      color(170, 255, 85),  
      color(85, 255, 170),  
      color(255, 255, 170), 
      color(170, 255, 255), 
      color(255, 170, 255), 
      color(170, 170, 255)  
    };
    
    
    int colorIndex = (int)(time * 10) % happyColors.length;
    color borderColor = happyColors[colorIndex];
    
    
    if (opacity < 255) {
      borderColor = color(red(borderColor), green(borderColor), blue(borderColor), opacity);
    }
    
    
    lowResCanvas.fill(255, opacity);  
    lowResCanvas.noStroke();
    lowResCanvas.rect(modalX, modalY, boxWidth, boxHeight, 12, 12, 12, 12);  
    
    
    lowResCanvas.noFill();
    lowResCanvas.stroke(borderColor);
    lowResCanvas.strokeWeight(2);
    lowResCanvas.rect(modalX, modalY, boxWidth, boxHeight, 12, 12, 12, 12);  
    
    
    if (modalShowColorPalette) {
      
      if (currentPenMode == PEN_MODE_REMOVE) {
        
        lowResCanvas.stroke(255, 0, 0, opacity);  
        lowResCanvas.strokeWeight(3);
        float xSize = 40;
        float centerX = modalX + boxWidth / 2;
        float centerY = modalY + boxHeight / 2;
        lowResCanvas.line(centerX - xSize/2, centerY - xSize/2, centerX + xSize/2, centerY + xSize/2);
        lowResCanvas.line(centerX - xSize/2, centerY + xSize/2, centerX + xSize/2, centerY - xSize/2);
        
        
        lowResCanvas.fill(255, 0, 0, opacity);
        lowResCanvas.noStroke();
        lowResCanvas.textAlign(CENTER, CENTER);
        lowResCanvas.textSize(8);
        lowResCanvas.text("N/A", centerX, centerY + xSize/2 + 10);
      } else {
        
        int boxSize = 20;
        int boxSpacing = 30;
        int colorCount = colorNames.length;
        int cols = min(5, colorCount);
        int rows = (colorCount + cols - 1) / cols;
        int totalWidth = cols * boxSpacing - (boxSpacing - boxSize);
        int totalHeight = rows * boxSpacing - (boxSpacing - boxSize);
        int startX = (int)(modalX + (boxWidth - totalWidth) / 2);
        int startY = (int)(modalY + (boxHeight - totalHeight) / 2);
        
        for (int i = 0; i < colorCount; i++) {
          int col = i % cols;
          int row = i / cols;
          int boxX = startX + col * boxSpacing;
          int boxY = startY + row * boxSpacing;
          
          
          if (i == colorCount - 1) {
            
            
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
          
          
          if (i == currentColorIndex) {
            
            lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
            lowResCanvas.strokeWeight(2);
          } else {
            lowResCanvas.stroke(128, opacity);  
            lowResCanvas.strokeWeight(1);
          }
          
          lowResCanvas.rect(boxX, boxY, boxSize, boxSize, 6, 6, 6, 6);  
        }
      }
    } else if (modalShowBrush) {
      
      float brushX = modalX + 20;
      float brushY = modalY + boxHeight/2;
      
      
      lowResCanvas.noFill();
      lowResCanvas.stroke(0, opacity);  
      lowResCanvas.strokeWeight(1);
      lowResCanvas.ellipse(brushX, brushY, brushSize, brushSize);
      
      
      lowResCanvas.fill(0, opacity);
      lowResCanvas.textAlign(LEFT, CENTER);
      lowResCanvas.textSize(10);
      lowResCanvas.noStroke();
      lowResCanvas.text(": " + (int)brushSize + "px", brushX + brushSize/2 + 8, brushY - 1);  
    } else if (modalShowPenMode) {
      
      int iconSize = 20;
      int iconSpacing = 30;
      boxWidth = 130;  
      int startX = (int)(modalX + (boxWidth - (4 * iconSpacing - (iconSpacing - iconSize))) / 2);
      
      for (int i = 0; i < 4; i++) {  
        int iconX = startX + i * iconSpacing;
        int iconY = (int)(modalY + boxHeight/2 - iconSize/2);
        
        
        if (i == currentPenMode) {
          
          lowResCanvas.fill(255, opacity);
          lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
          lowResCanvas.strokeWeight(2);
        } else {
          
          lowResCanvas.fill(240, opacity);
          lowResCanvas.stroke(128, opacity);
          lowResCanvas.strokeWeight(1);
        }
        
        lowResCanvas.rect(iconX, iconY, iconSize, iconSize, 6, 6, 6, 6);
        
        
        lowResCanvas.noStroke();
        if (i == PEN_MODE_DEFAULT) {
          
          lowResCanvas.fill(0, opacity);
          
          lowResCanvas.triangle(
            iconX + iconSize/2, iconY + 3,
            iconX + iconSize/2 - 3, iconY + 8,
            iconX + iconSize/2 + 3, iconY + 8
          );
          
          lowResCanvas.rect(iconX + iconSize/2 - 2, iconY + 8, 4, 9);
        } else if (i == PEN_MODE_REMOVE) {
          
          lowResCanvas.fill(255, 192, 203, opacity);  
          lowResCanvas.rect(iconX + 4, iconY + 6, 12, 8, 2, 2, 2, 2);
          
          lowResCanvas.stroke(180, 150, 160, opacity);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(iconX + 6, iconY + 8, iconX + 14, iconY + 8);
          lowResCanvas.line(iconX + 6, iconY + 12, iconX + 14, iconY + 12);
        } else if (i == PEN_MODE_IMAGE) {
          
          lowResCanvas.fill(255, 200, 0, opacity);  
          lowResCanvas.ellipse(iconX + iconSize/2, iconY + iconSize/2, 14, 14);
          
          lowResCanvas.fill(0, opacity);
          lowResCanvas.ellipse(iconX + iconSize/2 - 3, iconY + iconSize/2 - 2, 2, 2);
          lowResCanvas.ellipse(iconX + iconSize/2 + 3, iconY + iconSize/2 - 2, 2, 2);
          
          lowResCanvas.noFill();
          lowResCanvas.stroke(0, opacity);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.arc(iconX + iconSize/2, iconY + iconSize/2, 8, 8, 0.2, PI - 0.2);
        } else if (i == PEN_MODE_ANIMATION) {
          
          lowResCanvas.stroke(100, 100, 100, opacity);
          lowResCanvas.strokeWeight(1.5);
          lowResCanvas.noFill();
          
          
          
          float cx1 = iconX + iconSize/2;
          float cy1 = iconY + iconSize/2;
          float starSize = 4;
          
          lowResCanvas.line(cx1 - starSize, cy1, cx1 + starSize, cy1);
          lowResCanvas.line(cx1, cy1 - starSize, cx1, cy1 + starSize);
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(cx1 - starSize*0.7, cy1 - starSize*0.7, cx1 + starSize*0.7, cy1 + starSize*0.7);
          lowResCanvas.line(cx1 - starSize*0.7, cy1 + starSize*0.7, cx1 + starSize*0.7, cy1 - starSize*0.7);
          
          
          float cx2 = iconX + iconSize/2 + 5;
          float cy2 = iconY + iconSize/2 - 3;
          float smallSize = 2;
          lowResCanvas.strokeWeight(1);
          lowResCanvas.line(cx2 - smallSize, cy2, cx2 + smallSize, cy2);
          lowResCanvas.line(cx2, cy2 - smallSize, cx2, cy2 + smallSize);
          
          
          float cx3 = iconX + iconSize/2 - 5;
          float cy3 = iconY + iconSize/2 + 3;
          lowResCanvas.line(cx3 - smallSize, cy3, cx3 + smallSize, cy3);
          lowResCanvas.line(cx3, cy3 - smallSize, cx3, cy3 + smallSize);
        }
      }
    } else if (modalShowImagePreview) {
      
      int boxSize = 24;  
      int boxSpacing = 30;
      int startX = (int)(modalX + (boxWidth - (stampImageNames.length * boxSpacing - (boxSpacing - boxSize))) / 2);
      
      for (int i = 0; i < stampImageNames.length; i++) {
        int boxX = startX + i * boxSpacing;
        int boxY = (int)(modalY + boxHeight/2 - boxSize/2);
        
        
        if (i == currentImageIndex) {
          
          lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
          lowResCanvas.strokeWeight(2);
        } else {
          lowResCanvas.stroke(128, opacity);  
          lowResCanvas.strokeWeight(1);
        }
        
        
        lowResCanvas.fill(255, opacity);
        lowResCanvas.rect(boxX, boxY, boxSize, boxSize, 6, 6, 6, 6);
        
        
        if (stampImages != null && i < stampImages.length && stampImages[i] != null) {
          
          lowResCanvas.noSmooth();
          lowResCanvas.tint(255, opacity);
          lowResCanvas.imageMode(CENTER);
          lowResCanvas.image(stampImages[i], boxX + boxSize/2, boxY + boxSize/2, boxSize - 4, boxSize - 4);
          lowResCanvas.imageMode(CORNER);
          lowResCanvas.noTint();
        }
      }
    } else if (modalShowAnimationSelect) {
      int count = animatedPen.animationTypeNames.length;
      int boxSize = 24;  
      int boxSpacing = 30;
      int cols = min(5, count);
      int rows = (count + cols - 1) / cols;
      int totalWidth = cols * boxSpacing - (boxSpacing - boxSize);
      int totalHeight = rows * boxSpacing - (boxSpacing - boxSize);
      int startX = (int)(modalX + (boxWidth - totalWidth) / 2);
      int startY = (int)(modalY + (boxHeight - totalHeight) / 2);
      
      for (int i = 0; i < count; i++) {
        int col = i % cols;
        int row = i / cols;
        int boxX = startX + col * boxSpacing;
        int boxY = startY + row * boxSpacing;
        
        
        if (i == animatedPen.currentAnimationType) {
          
          lowResCanvas.stroke(red(borderColor), green(borderColor), blue(borderColor), opacity);
          lowResCanvas.strokeWeight(2);
        } else {
          lowResCanvas.stroke(128, opacity);  
          lowResCanvas.strokeWeight(1);
        }
        
        
        lowResCanvas.fill(255, opacity);
        lowResCanvas.rect(boxX, boxY, boxSize, boxSize, 6, 6, 6, 6);
        
        float iconOpacity = opacity / 255.0f;
        animatedPen.drawTypeIcon(lowResCanvas, i, boxX + boxSize / 2.0f, boxY + boxSize / 2.0f, boxSize * 0.8f, iconOpacity);
        
      }
      
      
      lowResCanvas.fill(0, opacity);
      lowResCanvas.textAlign(CENTER, TOP);
      lowResCanvas.textSize(8);
      lowResCanvas.noStroke();
      lowResCanvas.text(animatedPen.getCurrentTypeName(), modalX + boxWidth/2, modalY + boxHeight - 8);
    } else {
      
      lowResCanvas.fill(0, opacity);  
      lowResCanvas.textAlign(LEFT, TOP);
      lowResCanvas.noStroke();
      lowResCanvas.text(modalMessage, modalX + padding, modalY + 4);
    }
  }
}

void drawLowResUI() {
  
  
  
  float lowResMouseX = mouseX / displayScale;
  float lowResMouseY = mouseY / displayScale;
  
  
  if (currentPenMode == PEN_MODE_ANIMATION) {
    
    float time = millis() * 0.001;
    float pulseAmount = sin(time * 3) * 0.15;  
    float baseSize = animationSize;
    float pulseSize = baseSize * (1.0f + pulseAmount);
    float previewOpacity = 0.9f;
    
    if (!isSelectingZoom) {
      if (isZoomed) {
        float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
        float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
        
        lowResCanvas.pushMatrix();
        lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
        lowResCanvas.scale(zoomScale);
        animatedPen.drawTypePreview(lowResCanvas, animatedPen.currentAnimationType, canvasX, canvasY, pulseSize, previewOpacity);
        lowResCanvas.popMatrix();
      } else {
        animatedPen.drawTypePreview(lowResCanvas, animatedPen.currentAnimationType, lowResMouseX, lowResMouseY, pulseSize, previewOpacity);
      }
    }
  } else if (currentPenMode == PEN_MODE_IMAGE) {
    
    if (stampImages != null && currentImageIndex < stampImages.length && stampImages[currentImageIndex] != null) {
      PImage img = stampImages[currentImageIndex];
      
      
      if (isZoomed && !isSelectingZoom) {
        float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
        float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
        
        lowResCanvas.pushMatrix();
        lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
        lowResCanvas.scale(zoomScale);
        
        
        drawImageWithTransparency(lowResCanvas, img, canvasX, canvasY, imageStampSize, 128);
        
        lowResCanvas.popMatrix();
      } else if (!isSelectingZoom) {
        
        drawImageWithTransparency(lowResCanvas, img, lowResMouseX, lowResMouseY, imageStampSize, 128);
      }
    }
  } else {
    
    color brushColor;
    if (currentPenMode == PEN_MODE_REMOVE) {
      brushColor = color(255, 0, 0);  
    } else if (currentColorIndex == palette.length - 1) {
      
      float brushTime = millis() * 0.01;
      brushColor = color(
        (sin(brushTime) * 0.5 + 0.5) * 255,
        (sin(brushTime + 2.094) * 0.5 + 0.5) * 255,
        (sin(brushTime + 4.189) * 0.5 + 0.5) * 255
      );
    } else {
      brushColor = palette[currentColorIndex];
    }
    
    
    if (isZoomed && !isSelectingZoom) {
      float canvasX = (lowResMouseX - zoomOffsetX) / zoomScale;
      float canvasY = (lowResMouseY - zoomOffsetY) / zoomScale;
      
      lowResCanvas.noFill();
      lowResCanvas.stroke(brushColor);
      lowResCanvas.strokeWeight(1);  
      
      
      lowResCanvas.pushMatrix();
      lowResCanvas.translate(zoomOffsetX, zoomOffsetY);
      lowResCanvas.scale(zoomScale);
      
      float previewSize = (currentPenMode == PEN_MODE_REMOVE) ? brushSize * 5.0 : brushSize;
      lowResCanvas.ellipse(canvasX, canvasY, previewSize, previewSize);
      lowResCanvas.popMatrix();
    } else if (!isSelectingZoom) {
      
      lowResCanvas.noFill();
      lowResCanvas.stroke(brushColor);
      lowResCanvas.strokeWeight(1);  
      
      float previewSize = (currentPenMode == PEN_MODE_REMOVE) ? brushSize * 5.0 : brushSize;
      lowResCanvas.ellipse(lowResMouseX, lowResMouseY, previewSize, previewSize);
    }
  }
  
  
  if (showDebugInfo) {
    
    lowResCanvas.fill(0);  
    lowResCanvas.noStroke();
    lowResCanvas.textAlign(LEFT, TOP);
    lowResCanvas.textSize(8);  
    
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
  
  
  drawModal();
  
  
  if (pendingSave) {
    
    try {
      saveAndPrint(pendingPrint);
    } catch (Exception e) {
      println("Error during save: " + e.getMessage());
      showModal("SAVE ERROR", 2000);
    }
    pendingSave = false;
    pendingPrint = false;
  }

  
  if (pendingExportDialog) {
    try {
      
      cachedExportImage = renderFullCanvasToImage();
      
      selectOutput("Save as PNG:", "saveCanvasCallback", dataFile("canvas_" + year() + month() + day() + "_" + hour() + minute() + second() + ".png"));
    } catch (Exception e) {
      println("Error preparing export: " + e.getMessage());
      showModal("EXPORT ERROR", 2000);
    }
    pendingExportDialog = false;
  }
}

void mousePressed() {
  
  if (showStartupScreen) return;
  
  
  if (isSelectingZoom) {
    zoomSelectionStart.set(mouseX / displayScale, mouseY / displayScale);
    zoomSelectionEnd.set(mouseX / displayScale, mouseY / displayScale);
    return;
  }
  
  
  if (isSelectingZoom) {
    return;
  }
  
  if (mouseButton == LEFT) {
    
    if (currentPenMode == PEN_MODE_ANIMATION) {
      
      float canvasX, canvasY;
      if (isZoomed) {
        canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale;
      } else {
        canvasX = mouseX / displayScale;
        canvasY = mouseY / displayScale;
      }
      
      float globalY = canvasY + scrollY;
      int chunkY = ((int)globalY / CHUNK_HEIGHT) * CHUNK_HEIGHT;
      boolean chunkExists = chunkIndexMap.containsKey(chunkY);
      if (!chunkExists) {
        createChunk(chunkY);
      }
      saveUndoState();
      animatedPen.addAnimation(canvasX, canvasY, scrollY, animationSize);
      isDrawing = false; 
    } else if (currentPenMode == PEN_MODE_DEFAULT && lineCanvas != null) {
      
      float canvasX, canvasY;
      if (isZoomed) {
        canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
        canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
      } else {
        canvasX = mouseX / displayScale;
        canvasY = mouseY / displayScale + scrollY;
      }
      
      saveUndoState();
      lineCanvas.startStroke(canvasX, canvasY);
      if (currentColorIndex == palette.length - 1) {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], true);
      } else {
        lineCanvas.setColorAndRainbow(palette[currentColorIndex], false);
      }
      lineCanvas.setWeight(brushSize);
      isDrawing = true;
      isErasing = false;  
    } else if (currentPenMode == PEN_MODE_REMOVE) {
      
      captureUndoState = true;
      isDrawing = true;
      isErasing = true;  
    } else {
      
      captureUndoState = true;
      isDrawing = true;
      isErasing = false;
    }
  } else if (mouseButton == RIGHT) {
    
    return;
  }
  
  
  if (isZoomed) {
    float canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
    float canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
    prevMouse.set(canvasX, canvasY);
  } else {
    prevMouse.set(mouseX / displayScale, mouseY / displayScale + scrollY);
  }
}

void mouseReleased() {
  
  if (showStartupScreen) return;
  
  
  if (isSelectingZoom && zoomSelectionStart.x >= 0) {
    
    float x1 = min(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y1 = min(zoomSelectionStart.y, zoomSelectionEnd.y);
    float x2 = max(zoomSelectionStart.x, zoomSelectionEnd.x);
    float y2 = max(zoomSelectionStart.y, zoomSelectionEnd.y);
    
    float selWidth = x2 - x1;
    float selHeight = y2 - y1;
    
    
    if (selWidth > 20 && selHeight > 20) {
      
      float scaleX = CANVAS_WIDTH / selWidth;
      float scaleY = SCREEN_HEIGHT / selHeight;
      zoomScale = min(scaleX, scaleY);
      
      
      zoomScale = constrain(zoomScale, 1.5, 10.0);
      
      
      float centerX = (x1 + x2) / 2;
      float centerY = (y1 + y2) / 2;
      
      
      zoomOffsetX = CANVAS_WIDTH / 2 - centerX * zoomScale;
      zoomOffsetY = SCREEN_HEIGHT / 2 - centerY * zoomScale;
      
      
      isZoomed = true;
      isSelectingZoom = false;
      clearPersistentModal();  
      showModal("ZOOMED: " + nf(zoomScale, 1, 1) + "x", 1500);
    } else {
      
      zoomSelectionStart.set(-1, -1);
      zoomSelectionEnd.set(-1, -1);
    }
  } else {
    
    if (currentPenMode == PEN_MODE_DEFAULT && lineCanvas != null) {
      
      if (isDrawing && prevMouse.x >= 0 && prevMouse.y >= 0) {
        
        lineCanvas.endStroke();
      } else if (isDrawing) {
        
        float canvasX, canvasY;
        if (isZoomed) {
          canvasX = (mouseX / displayScale - zoomOffsetX) / zoomScale;
          canvasY = (mouseY / displayScale - zoomOffsetY) / zoomScale + scrollY;
        } else {
          canvasX = mouseX / displayScale;
          canvasY = mouseY / displayScale + scrollY;
        }
        
        lineCanvas.endStroke();
      }
    }
    isDrawing = false;
    isErasing = false;
    prevMouse.set(-1, -1);
  }
}

void mouseMoved() {
  
}

void mouseDragged() {
  
  if (isSelectingZoom) {
    zoomSelectionEnd.set(mouseX / displayScale, mouseY / displayScale);
    return;
  }
  
  
}

void mouseWheel(MouseEvent event) {
  
  if (showStartupScreen) return;
  
  
  if (isZoomed) {
    return;
  }
  
  
  float maxScroll = getMaxContentY() - SCREEN_HEIGHT;
  scrollY += event.getCount() * 0.7;  
  scrollY = constrain(scrollY, 0, max(0, maxScroll));
}

void keyReleased() {
  
  if (key == TAB) {
    showDebugInfo = false;
  }
}

void keyPressed() {
  
  if (showStartupScreen) {
    if (key == ENTER || key == RETURN) {
      showStartupScreen = false;
      println("Starting paint application...");
    }
    return;  
  }
  
  
  if (key == ESC) {
    key = 0;  
    exit();   
    return;
  }
  
  
  if (key == TAB) {
    showDebugInfo = true;
    return;
  }
  
  
  boolean isMac = System.getProperty("os.name").toLowerCase().contains("mac");
  boolean cmdPressed = isMac ? (keyEvent.isMetaDown()) : (keyEvent.isControlDown());
  
  if (cmdPressed) {
    if (key == 's' || key == 'S') {
      
      pendingExportDialog = true;
      return;
    } else if (key == 'z' || key == 'Z') {
      if (keyEvent.isShiftDown()) {
        
        pendingRedo = true;
      } else {
        
        pendingUndo = true;
      }
      return;
    }
  }
  
  
  if (key == ' ') {
    if (isZoomed) {
      
      isZoomed = false;
      zoomScale = 1.0;
      zoomOffsetX = 0;
      zoomOffsetY = 0;
      showModal("ZOOM EXIT");
    } else if (isSelectingZoom) {
      
      isSelectingZoom = false;
      zoomSelectionStart.set(-1, -1);
      zoomSelectionEnd.set(-1, -1);
      clearPersistentModal();  
      showModal("ZOOM CANCELLED");
    } else {
      
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
      
      pendingSave = true;
      pendingPrint = true;
      break;
  }
  
  if (key == CODED) {
    
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



float getMaxContentY() {
  if (chunkPositions.isEmpty()) return CHUNK_HEIGHT;  
  
  int maxY = 0;
  for (int chunkY : chunkPositions) {
    maxY = max(maxY, chunkY + CHUNK_HEIGHT);
  }
  
  
  return maxY + CHUNK_HEIGHT;
}

void saveAndPrint(boolean printToReceipt) {
  println("=== SAVE AND PRINT ===");
  
  
  boolean hasChunks = !chunkTextures.isEmpty();
  boolean hasLines = (lineCanvas != null && !lineCanvas.lines.isEmpty());
  
  if (!hasChunks && !hasLines) {
    println("Nothing to save");
    return;
  }
  
  
  int minY = Integer.MAX_VALUE;
  int maxY = Integer.MIN_VALUE;
  
  
  if (hasChunks) {
    for (int i = 0; i < chunkPositions.size(); i++) {
      int chunkY = chunkPositions.get(i);
      minY = min(minY, chunkY);
      maxY = max(maxY, chunkY + CHUNK_HEIGHT);
    }
  }
  
  
  if (hasLines) {
    minY = min(minY, (int)lineCanvas.getMinY());
    maxY = max(maxY, (int)lineCanvas.getMaxY());
  }
  
  
  if (minY == Integer.MAX_VALUE) {
    minY = 0;
    maxY = SCREEN_HEIGHT;
  }
  
  println("Saving from Y=" + minY + " to Y=" + maxY);
  
  
  
  PImage screenCapture = get(0, 0, width, height);
  
  
  
  PImage finalImage = createImage(CANVAS_WIDTH, maxY - minY, RGB);
  finalImage.loadPixels();
  
  
  float savedScrollY = scrollY;
  
  
  for (int y = minY; y < maxY; y += SCREEN_HEIGHT) {
    
    lowResCanvas.beginDraw();
    lowResCanvas.background(255);
    
    
    int startChunkY = max(0, (int)(y / CHUNK_HEIGHT) * CHUNK_HEIGHT);
    int endChunkY = (int)((y + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;
    
    
    for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
      Integer chunkIdx = chunkIndexMap.get(chunkY);
      if (chunkIdx != null) {
        PGraphics chunk = chunkTextures.get(chunkIdx);
        float renderY = chunkY - y;  
        lowResCanvas.image(chunk, 0, renderY);
      }
    }
    
    
    if (lineCanvas != null) {
      lineCanvas.scrollTo(y);
      lineCanvas.update(0); 
      lineCanvas.draw(lowResCanvas, false, 1.0, 0, 0);
    }
    
    
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
  
  
  String filename = "output.png";
  finalImage.save(filename);
  println("Saved: " + filename + " (" + CANVAS_WIDTH + "x" + (maxY-minY) + ")");
  
  
  
  showModal("SAVED: " + filename, 2000);
  
  
  if (printToReceipt) {
    printToThermalPrinter(filename);
  }
}


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
    
    lowResCanvas.beginDraw();
    lowResCanvas.background(255);

    int startChunkY = max(0, (int)(y / CHUNK_HEIGHT) * CHUNK_HEIGHT);
    int endChunkY = (int)((y + SCREEN_HEIGHT) / CHUNK_HEIGHT + 1) * CHUNK_HEIGHT;

    
    for (int chunkY = startChunkY; chunkY <= endChunkY; chunkY += CHUNK_HEIGHT) {
      Integer chunkIdx = chunkIndexMap.get(chunkY);
      if (chunkIdx != null) {
        PGraphics chunk = chunkTextures.get(chunkIdx);
        float renderY = chunkY - y;
        lowResCanvas.image(chunk, 0, renderY);
      }
    }

    
    if (lineCanvas != null) {
      lineCanvas.scrollTo(y);
      lineCanvas.update(0);
      lineCanvas.draw(lowResCanvas, false, 1.0, 0, 0);
    }

    
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
    
    String scriptPath = sketchPath("munbyn_printer.py");
    String imagePath = sketchPath(filename);
    
    
    ProcessBuilder pb = new ProcessBuilder("python3", scriptPath, imagePath);
    pb.redirectErrorStream(true);
    Process p = pb.start();
    
    
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


void initMIDI() {
  try {
    MidiDevice.Info[] infos = MidiSystem.getMidiDeviceInfo();
    
    println("\nAvailable MIDI devices:");
    for (int i = 0; i < infos.length; i++) {
      println("[" + i + "] " + infos[i].getName() + " - " + infos[i].getDescription());
    }
    
    
    for (MidiDevice.Info info : infos) {
      if (info.getName().contains("Arduino Leonardo")) {
        MidiDevice device = MidiSystem.getMidiDevice(info);
        
        
        if (device.getMaxTransmitters() != 0) {
          device.open();
          
          
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


class MidiReceiver implements Receiver {
  public void send(MidiMessage message, long timeStamp) {
    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      
      
      if (sm.getCommand() == ShortMessage.CONTROL_CHANGE) {
        int channel = sm.getChannel() + 1;  
        int ccNumber = sm.getData1();
        int value = sm.getData2();
        
        
        if (ccNumber == 1) {
          
          
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
          
          
          pendingPenMode = newPenMode;
          
          
          println("MIDI CC1: value=" + value + " → Pen mode = " + penModeNames[newPenMode]);
        }
        
        
        if (ccNumber == 2) {
          if (currentPenMode == PEN_MODE_IMAGE) {
            
            
            
            int newImageIndex = value < 64 ? 0 : 1;
            
            
            pendingImageIndex = newImageIndex;
            
            
            println("MIDI CC2: value=" + value + " → Image = " + stampImageNames[newImageIndex]);
          } else if (currentPenMode == PEN_MODE_ANIMATION) {
            
            if (animatedPen != null && animatedPen.animationTypeNames.length > 0) {
              int maxIndex = animatedPen.animationTypeNames.length - 1;
              int newType = (int)map(value, 0, 127, 0, maxIndex);
              newType = constrain(newType, 0, maxIndex);
              animatedPen.setAnimationType(newType);
              println("MIDI CC2: value=" + value + " → Animation = " + animatedPen.getTypeName(newType));
              showAnimationTypeModal();
            }
          } else {
            
            
            
            int paletteSize = colorNames.length;
            int newColorIndex = constrain(value * paletteSize / 128, 0, paletteSize - 1);
            
            
            pendingColorIndex = newColorIndex;
            
            
            println("MIDI CC2: value=" + value + " → Color = " + colorNames[newColorIndex]);
          }
        }
        
        
        if (ccNumber == 3) {
          if (currentPenMode == PEN_MODE_IMAGE) {
            
            float newImageSize = map(value, 0, 127, 10, 128);
            newImageSize = constrain(newImageSize, 10, 128);
            
            
            pendingImageSize = newImageSize;
            
            
            println("MIDI CC3: value=" + value + " → Image size = " + (int)newImageSize + "px");
          } else if (currentPenMode == PEN_MODE_ANIMATION) {
            
            float newAnimSize = map(value, 0, 127, 10, 100);
            newAnimSize = constrain(newAnimSize, 10, 100);
            
            
            animationSize = newAnimSize;
            showAnimationSizeModal();
            
            
            println("MIDI CC3: value=" + value + " → Animation size = " + (int)newAnimSize + "px");
          } else {
            
            float newBrushSize = map(value, 0, 127, 1, 8);
            newBrushSize = constrain(newBrushSize, 1, 8);
            
            
            pendingBrushSize = newBrushSize;
            
            
            println("MIDI CC3: value=" + value + " → Brush size = " + (int)newBrushSize + "px");
          }
        }
        
        
        if (ccNumber == 4) {
          if (currentPenMode == PEN_MODE_DEFAULT) {
            
            float newAnimSpeed = value / 127.0;  
            newAnimSpeed = constrain(newAnimSpeed, 0, 1.0);
            
            
            pendingAnimationSpeed = newAnimSpeed;
            
            
            int speedPercent = (int)(newAnimSpeed * 100);
            println("MIDI CC4: value=" + value + " → Line animation speed = " + speedPercent + "%");
          } else if (currentPenMode == PEN_MODE_ANIMATION) {
            
            float newParam = value / 127.0f;  
            newParam = constrain(newParam, 0, 1.0);
            
            if (animatedPen != null) {
              animatedPen.setAnimationParameter(newParam);
              pendingAnimationSpeed = -3;
              pendingAnimationParamValue = newParam;
              pendingAnimationParamLabel = animatedPen.getCurrentParamLabel();
              int percent = (int)(newParam * 100);
              println("MIDI CC4: value=" + value + " → " + pendingAnimationParamLabel + " = " + percent + "%");
            }
          } else {
            
            pendingAnimationSpeed = -2;  
            
            
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
    
  }
}


void drawStartupScreen() {
  
  startupAnimTime += deltaSeconds;

  
  background(255);

  
  float leftPanelWidth = width * 0.5;
  float rightPanelStart = leftPanelWidth;
  float rightPanelWidth = width - leftPanelWidth; 
  float centerY = height * 0.5;

  
  stroke(200);
  strokeWeight(1);
  line(leftPanelWidth, 0, leftPanelWidth, height);

  
  float maxImg = min(leftPanelWidth, height) * 0.48; 
  float imgW = maxImg;
  float imgH = maxImg;

  
  float txtSize = max(18, min(width, height) * 0.04);
  textSize(txtSize);
  float textH = textAscent() + textDescent();
  float gap = 24; 

  
  float groupH = imgH + gap + textH;
  float groupTopY = centerY - groupH * 0.5;

  
  if (stampImages != null && stampImages.length > 0 && stampImages[0] != null) {
    imageMode(CENTER);
    noSmooth();
    image(stampImages[0], leftPanelWidth * 0.5, groupTopY + imgH * 0.5, imgW, imgH);
    imageMode(CORNER);
  }

  
  textAlign(CENTER, CENTER);
  float blinkAlpha = (sin(startupAnimTime * 4) * 0.5 + 0.5) * 255;
  fill(0, blinkAlpha);
  text("Press ENTER to start", leftPanelWidth * 0.5, groupTopY + imgH + gap + textH * 0.5);

  
  float rightCenterX = rightPanelStart + rightPanelWidth * 0.5;
  float lineHeight = 22;
  float sectionSpacing = 35;

  
  int drawingLines = 6; 
  int systemLines = 5;  
  int midiLines = midiConnected ? 4 : 0;
  int canvasInfoLines = 3; 
  boolean hasStampsInfo = (stampImages != null && stampImageNames != null && stampImageNames.length > 0);
  int extraInfoLines = (hasStampsInfo ? 1 : 0) + 1; 

  float totalH = 0;
  totalH += 40; 
  totalH += lineHeight  + drawingLines * lineHeight + sectionSpacing;
  totalH += lineHeight  + systemLines * lineHeight + sectionSpacing;
  if (midiConnected) {
    totalH += lineHeight  + midiLines * lineHeight + sectionSpacing;
  }
  totalH += lineHeight  + (canvasInfoLines + extraInfoLines) * lineHeight;

  float currentY = centerY - totalH * 0.5;

  
  textSize(24);
  fill(0);
  textAlign(CENTER, TOP);
  text("CONTROLS & FEATURES", rightCenterX, currentY);
  currentY += 40;

  
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

  
  textAlign(LEFT, TOP);
}


void updateGifAnimations() {
  int currentTime = millis();
  
  
  if (currentTime - lastFrameUpdate > frameUpdateInterval) {
    for (int i = 0; i < stampImageNames.length; i++) {
      if (isAnimated[i] && gifFrames[i] != null && totalFrames[i] > 0) {
        
        currentFrameIndex[i] = (currentFrameIndex[i] + 1) % totalFrames[i];
        stampImages[i] = gifFrames[i][currentFrameIndex[i]];
      }
    }
    lastFrameUpdate = currentTime;
  }
}


void drawImageWithTransparency(PGraphics canvas, PImage img, float x, float y, float size, int alpha) {
  
  canvas.noSmooth();  
  canvas.tint(255, alpha);  
  canvas.imageMode(CENTER);
  canvas.image(img, x, y, size, size);
  canvas.imageMode(CORNER);
  canvas.noTint();  
}


void exit() {
  
  if (midiDevice != null && midiDevice.isOpen()) {
    try {
      midiDevice.close();
    } catch (Exception e) {
      
    }
  }
  
  
  super.exit();
}


void exportPNGWithDialog() {
  
  pendingExportDialog = true;
}


void saveCanvasCallback(File selection) {
  if (selection == null) {
    showModal("EXPORT CANCELLED", 1000);
    
    cachedExportImage = null;
    return;
  }
  
  
  String filename = selection.getAbsolutePath();
  if (!filename.toLowerCase().endsWith(".png")) {
    filename += ".png";
  }
  
  
  if (cachedExportImage == null) {
    
    cachedExportImage = renderFullCanvasToImage();
  }
  if (cachedExportImage != null) {
    cachedExportImage.save(filename);
  } else {
    showModal("NO CONTENT TO SAVE", 1500);
    return;
  }
  
  cachedExportImage = null;
  
  
  String displayName = new File(filename).getName();
  showModal("EXPORTED: " + displayName, 2000);
  println("Exported canvas to: " + filename);
}
