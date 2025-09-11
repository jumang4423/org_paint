# Infinite Canvas Paint App for Thermal Printer

## Project Overview
A Processing-based painting application with GLSL shaders, designed for creating artwork that can be printed on thermal printer receipts for exhibition.

## Technical Specifications

### Canvas
- **Width**: 576px (fixed) - matches thermal printer width
- **Height**: Infinite scrollable canvas
- **Display**: Shows only visible portion (screen height based on 16:9 ratio from width)
- **Scroll**: Vertical scrolling to navigate the infinite canvas

### Rendering
- **Technology**: Processing with GLSL shaders
- **Buffer**: Store painting data in GLSL buffers (texture/framebuffer)
- **Optimization**: Render only visible chunks
- **Chunk System**: Divide canvas into manageable chunks for performance

### Drawing Features
- **Modes**: Draw and Erase
- **Color**: Monochrome (black on white, suitable for thermal printer)
- **Brush Size**: Adjustable
- **Input**: Mouse position and state

### GLSL Uniforms
All drawing parameters passed as uniforms:
- Mouse position (x, y)
- Paint mode (draw/erase)
- Brush size
- Current scroll offset (y position)
- Visible viewport bounds

### Future Enhancements
- Neural network integration for generative effects
- Complex shader-based image processing
- Pattern generation algorithms
- Procedural textures

### Output
- Final artwork exported for thermal printer (58mm width standard)
- Receipt format for gallery exhibition
- Continuous roll printing capability

## Implementation Notes
- Use PGraphics or Framebuffer Object (FBO) for off-screen rendering
- Implement chunk loading/unloading based on scroll position
- Maintain drawing state across chunks
- Optimize shader performance for real-time interaction

## Testing Commands
```bash
# Run the Processing sketch
processing-java --sketch=`pwd` --run
```

## Build Requirements
- Processing 4.x
- GLSL 1.20+ support
- P2D or P3D renderer for shader support