// AnimatedPen class - manages particle animations placed on canvas
class AnimatedPen {
  ArrayList<AnimationInstance> animations;

  static final int ANIM_CLOUD = 0;
  static final int ANIM_STAR = 1;
  static final int ANIM_RIBBON = 2;
  static final int ANIM_FLOWER = 3;
  static final int ANIM_CANDY = 4;
  static final int ANIM_FIREFLY = 5;
  static final int ANIM_CONFETTI = 6;
  static final int ANIM_CATER = 7;

  int currentAnimationType = ANIM_CLOUD;
  String[] animationTypeNames = {
    "CLOUD",
    "STAR",
    "RIBBON",
    "FLOWER",
    "CANDY",
    "FIREFLY",
    "CONFETTI",
    "BUG"
  };
  String[] animationParamLabels = {
    "Cloud density",
    "Sparkle twinkle",
    "Ribbon flutter",
    "Bloom spin",
    "Candy scatter",
    "Firefly glow",
    "Confetti burst",
    "Bug speed"
  };
  float[] animationParamDefaults = {
    0.5f, // cloud density
    0.6f, // star sparkle
    0.5f, // ribbon density
    0.6f, // flower amount
    0.5f, // candy scatter
    0.5f, // firefly glow
    0.6f, // confetti amount
    0.5f  // bug speed
  };
  float[] animationParamValues;
  float globalCloudDensity = 0.5f; // Maintained for backwards compatibility
  
  AnimatedPen() {
    animations = new ArrayList<AnimationInstance>();
    animationParamValues = animationParamDefaults.clone();
    globalCloudDensity = animationParamValues[ANIM_CLOUD];
  }
  
  // Add new animation at position with size
  void addAnimation(float x, float y, float scrollY, float size) {
    AnimationInstance anim = null;
    
    switch(currentAnimationType) {
      case ANIM_CLOUD:
        anim = new CloudAnimation(x, y + scrollY, size, animationParamValues[ANIM_CLOUD]);
        break;
      case ANIM_STAR:
        anim = new StarSparkleAnimation(x, y + scrollY, size, animationParamValues[ANIM_STAR]);
        break;
      case ANIM_RIBBON:
        anim = new RibbonFlutterAnimation(x, y + scrollY, size, animationParamValues[ANIM_RIBBON]);
        break;
      case ANIM_FLOWER:
        anim = new FlowerBloomAnimation(x, y + scrollY, size, animationParamValues[ANIM_FLOWER]);
        break;
      case ANIM_CANDY:
        anim = new CandyPopAnimation(x, y + scrollY, size, animationParamValues[ANIM_CANDY]);
        break;
      case ANIM_FIREFLY:
        anim = new FireflyDriftAnimation(x, y + scrollY, size, animationParamValues[ANIM_FIREFLY]);
        break;
      case ANIM_CONFETTI:
        anim = new ConfettiBurstAnimation(x, y + scrollY, size, animationParamValues[ANIM_CONFETTI]);
        break;
      case ANIM_CATER:
        anim = new CaterpillarAnimation(x, y + scrollY, size, animationParamValues[ANIM_CATER]);
        break;
    }
    
    if (anim != null) {
      animations.add(anim);
    }
  }
  
  // Set cloud density for new animations (doesn't affect existing ones)
  void setCloudDensity(float density) {
    float clamped = constrain(density, 0, 1.0);
    globalCloudDensity = clamped;
    if (animationParamValues != null && animationParamValues.length > ANIM_CLOUD) {
      animationParamValues[ANIM_CLOUD] = clamped;
    }
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

  String getTypeName(int type) {
    if (type >= 0 && type < animationTypeNames.length) {
      return animationTypeNames[type];
    }
    return "?";
  }

  String getParamLabel(int type) {
    if (type >= 0 && type < animationParamLabels.length) {
      return animationParamLabels[type];
    }
    return "PARAM";
  }

  String getCurrentParamLabel() {
    return getParamLabel(currentAnimationType);
  }

  float getAnimationParam(int type) {
    if (type >= 0 && type < animationParamValues.length) {
      return animationParamValues[type];
    }
    return 0.5f;
  }

  float getCurrentParamValue() {
    return getAnimationParam(currentAnimationType);
  }

  void setAnimationParameter(float value) {
    float clamped = constrain(value, 0, 1.0f);
    animationParamValues[currentAnimationType] = clamped;
    if (currentAnimationType == ANIM_CLOUD) {
      globalCloudDensity = clamped;
    }
  }

  void setAnimationType(int type) {
    if (animationTypeNames.length == 0) return;
    currentAnimationType = max(0, min(animationTypeNames.length - 1, type));
  }

  void drawTypeIcon(PGraphics canvas, int type, float centerX, float centerY, float size, float opacity) {
    canvas.pushStyle();
    float alpha = constrain(opacity, 0, 1);

    switch(type) {
      case ANIM_CLOUD:
        canvas.noFill();
        canvas.stroke(160, 160, 160, alpha * 255);
        canvas.strokeWeight(1);
        canvas.ellipse(centerX - size * 0.25f, centerY + size * 0.1f, size * 0.8f, size * 0.45f);
        canvas.ellipse(centerX + size * 0.25f, centerY + size * 0.1f, size * 0.8f, size * 0.45f);
        canvas.ellipse(centerX, centerY - size * 0.15f, size, size * 0.55f);
        break;
      case ANIM_STAR:
        canvas.stroke(255, 220, 140, alpha * 255);
        canvas.strokeWeight(1.4f);
        canvas.line(centerX - size * 0.5f, centerY, centerX + size * 0.5f, centerY);
        canvas.line(centerX, centerY - size * 0.5f, centerX, centerY + size * 0.5f);
        canvas.stroke(255, 150, 220, alpha * 255);
        canvas.strokeWeight(1);
        canvas.line(centerX - size * 0.35f, centerY - size * 0.35f, centerX + size * 0.35f, centerY + size * 0.35f);
        canvas.line(centerX - size * 0.35f, centerY + size * 0.35f, centerX + size * 0.35f, centerY - size * 0.35f);
        canvas.noStroke();
        canvas.fill(255, 255, 255, alpha * 220);
        canvas.ellipse(centerX, centerY, size * 0.3f, size * 0.3f);
        break;
      case ANIM_RIBBON:
        canvas.noFill();
        canvas.stroke(255, 180, 220, alpha * 255);
        canvas.strokeWeight(2);
        canvas.bezier(centerX - size * 0.5f, centerY - size * 0.2f,
                      centerX - size * 0.2f, centerY - size * 0.6f,
                      centerX + size * 0.2f, centerY + size * 0.6f,
                      centerX + size * 0.5f, centerY + size * 0.2f);
        canvas.stroke(180, 220, 255, alpha * 230);
        canvas.strokeWeight(1.2f);
        canvas.bezier(centerX - size * 0.55f, centerY + size * 0.3f,
                      centerX - size * 0.1f, centerY,
                      centerX + size * 0.1f, centerY,
                      centerX + size * 0.55f, centerY - size * 0.3f);
        break;
      case ANIM_FLOWER:
        canvas.noStroke();
        canvas.fill(255, 210, 230, alpha * 230);
        for (int i = 0; i < 6; i++) {
          float angle = TWO_PI * i / 6.0f;
          float px = centerX + cos(angle) * size * 0.4f;
          float py = centerY + sin(angle) * size * 0.4f;
          canvas.ellipse(px, py, size * 0.55f, size * 0.35f);
        }
        canvas.fill(255, 240, 140, alpha * 255);
        canvas.ellipse(centerX, centerY, size * 0.45f, size * 0.45f);
        break;
      case ANIM_CANDY:
        canvas.noStroke();
        canvas.fill(255, 120, 170, alpha * 230);
        canvas.ellipse(centerX - size * 0.25f, centerY - size * 0.1f, size * 0.35f, size * 0.35f);
        canvas.fill(255, 200, 90, alpha * 230);
        canvas.rectMode(CENTER);
        canvas.rect(centerX + size * 0.2f, centerY + size * 0.05f, size * 0.35f, size * 0.35f, size * 0.1f);
        canvas.rectMode(CORNER);
        canvas.fill(255, 255, 255, alpha * 200);
        canvas.ellipse(centerX - size * 0.15f, centerY - size * 0.2f, size * 0.18f, size * 0.18f);
        break;
      case ANIM_FIREFLY:
        canvas.noStroke();
        canvas.fill(255, 240, 170, alpha * 120);
        canvas.ellipse(centerX, centerY, size, size);
        canvas.fill(255, 255, 200, alpha * 220);
        canvas.ellipse(centerX, centerY, size * 0.45f, size * 0.45f);
        canvas.stroke(255, 240, 160, alpha * 160);
        canvas.strokeWeight(1.2f);
        canvas.line(centerX - size * 0.45f, centerY + size * 0.2f, centerX - size * 0.1f, centerY - size * 0.15f);
        canvas.line(centerX - size * 0.1f, centerY - size * 0.15f, centerX + size * 0.4f, centerY - size * 0.35f);
        break;
      case ANIM_CONFETTI:
        canvas.noStroke();
        canvas.fill(255, 110, 170, alpha * 255);
        canvas.rect(centerX - size * 0.4f, centerY - size * 0.3f, size * 0.2f, size * 0.6f);
        canvas.fill(120, 200, 255, alpha * 255);
        canvas.triangle(centerX + size * 0.05f, centerY - size * 0.35f,
                        centerX + size * 0.35f, centerY - size * 0.05f,
                        centerX - size * 0.05f, centerY + size * 0.05f);
        canvas.fill(255, 200, 90, alpha * 255);
        canvas.rect(centerX - size * 0.15f, centerY + size * 0.1f, size * 0.45f, size * 0.18f);
        break;
      case ANIM_CATER:
        canvas.stroke(40, 80, 35, alpha * 255);
        canvas.strokeWeight(1.2f);
        for (int i = 0; i < 4; i++) {
          float segX = centerX - size * 0.45f + i * size * 0.3f;
          float segRadius = size * (0.35f - i * 0.03f);
          canvas.fill(130 - i * 6, 205 - i * 5, 120 - i * 4, alpha * 255);
          canvas.ellipse(segX, centerY, segRadius, segRadius * 0.75f);
        }
        canvas.noStroke();
        canvas.fill(255, 255, 255, alpha * 220);
        canvas.ellipse(centerX + size * 0.2f, centerY - size * 0.12f, size * 0.18f, size * 0.2f);
        canvas.fill(0, alpha * 255);
        canvas.ellipse(centerX + size * 0.18f, centerY - size * 0.12f, size * 0.07f, size * 0.09f);
        break;
    }

    canvas.popStyle();
  }

  void drawTypePreview(PGraphics canvas, int type, float centerX, float centerY, float baseSize, float opacity) {
    canvas.pushStyle();
    float alpha = constrain(opacity, 0, 1);

    switch(type) {
      case ANIM_CLOUD:
        canvas.noFill();
        canvas.stroke(160, 160, 160, alpha * 220);
        canvas.strokeWeight(1.8f);
        canvas.ellipse(centerX - baseSize * 0.4f, centerY + baseSize * 0.15f, baseSize * 1.4f, baseSize * 0.8f);
        canvas.ellipse(centerX + baseSize * 0.4f, centerY + baseSize * 0.15f, baseSize * 1.4f, baseSize * 0.8f);
        canvas.ellipse(centerX, centerY - baseSize * 0.2f, baseSize * 1.6f, baseSize * 0.9f);
        break;
      case ANIM_STAR:
        drawTypeIcon(canvas, type, centerX, centerY, baseSize, alpha);
        canvas.stroke(255, 200, 255, alpha * 160);
        canvas.strokeWeight(1);
        canvas.ellipse(centerX + baseSize * 0.6f, centerY - baseSize * 0.2f, baseSize * 0.3f, baseSize * 0.3f);
        canvas.ellipse(centerX - baseSize * 0.65f, centerY + baseSize * 0.3f, baseSize * 0.25f, baseSize * 0.25f);
        break;
      case ANIM_RIBBON:
        canvas.noFill();
        canvas.stroke(255, 160, 220, alpha * 240);
        canvas.strokeWeight(3);
        canvas.bezier(centerX - baseSize, centerY - baseSize * 0.4f,
                      centerX - baseSize * 0.3f, centerY - baseSize,
                      centerX + baseSize * 0.3f, centerY + baseSize,
                      centerX + baseSize, centerY + baseSize * 0.4f);
        canvas.stroke(190, 220, 255, alpha * 220);
        canvas.strokeWeight(2);
        canvas.bezier(centerX - baseSize, centerY + baseSize * 0.4f,
                      centerX - baseSize * 0.1f, centerY,
                      centerX + baseSize * 0.1f, centerY,
                      centerX + baseSize, centerY - baseSize * 0.4f);
        break;
      case ANIM_FLOWER:
        canvas.stroke(170, 170, 170, alpha * 255);
        canvas.strokeWeight(1.1f);
        for (int i = 0; i < 6; i++) {
          float angle = TWO_PI * i / 6.0f;
          float px = centerX + cos(angle) * baseSize * 0.45f;
          float py = centerY + sin(angle) * baseSize * 0.45f;
          canvas.fill(255, 255, 255, alpha * 235);
          canvas.ellipse(px, py, baseSize * 0.55f, baseSize * 0.35f);
        }
        canvas.noStroke();
        canvas.fill(255, 215, 90, alpha * 255);
        canvas.ellipse(centerX, centerY, baseSize * 0.65f, baseSize * 0.65f);
        break;
      case ANIM_CANDY:
        canvas.noStroke();
        canvas.fill(255, 120, 170, alpha * 230);
        canvas.ellipse(centerX - baseSize * 0.5f, centerY - baseSize * 0.15f, baseSize * 0.8f, baseSize * 0.8f);
        canvas.fill(120, 200, 255, alpha * 230);
        canvas.beginShape();
        canvas.vertex(centerX + baseSize * 0.45f, centerY - baseSize * 0.6f);
        canvas.vertex(centerX + baseSize * 0.9f, centerY);
        canvas.vertex(centerX + baseSize * 0.45f, centerY + baseSize * 0.6f);
        canvas.vertex(centerX + baseSize * 0.1f, centerY);
        canvas.endShape(CLOSE);
        canvas.fill(255, 200, 90, alpha * 230);
        canvas.beginShape();
        canvas.vertex(centerX, centerY + baseSize * 0.6f);
        canvas.bezierVertex(centerX + baseSize * 0.5f, centerY + baseSize * 0.1f,
                            centerX + baseSize * 0.3f, centerY - baseSize * 0.6f,
                            centerX, centerY - baseSize * 0.2f);
        canvas.bezierVertex(centerX - baseSize * 0.3f, centerY - baseSize * 0.6f,
                            centerX - baseSize * 0.5f, centerY + baseSize * 0.1f,
                            centerX, centerY + baseSize * 0.6f);
        canvas.endShape(CLOSE);
        break;
      case ANIM_FIREFLY:
        canvas.stroke(255, 240, 160, alpha * 180);
        canvas.strokeWeight(baseSize * 0.08f);
        canvas.line(centerX - baseSize * 0.8f, centerY + baseSize * 0.2f,
                    centerX - baseSize * 0.1f, centerY - baseSize * 0.15f);
        canvas.line(centerX - baseSize * 0.1f, centerY - baseSize * 0.15f,
                    centerX + baseSize * 0.7f, centerY - baseSize * 0.4f);
        canvas.noStroke();
        canvas.fill(255, 240, 140, alpha * 120);
        canvas.ellipse(centerX, centerY, baseSize * 1.4f, baseSize * 1.4f);
        canvas.fill(255, 255, 200, alpha * 220);
        canvas.ellipse(centerX, centerY, baseSize * 0.6f, baseSize * 0.6f);
        canvas.fill(255, 255, 255, alpha * 220);
        canvas.ellipse(centerX + baseSize * 0.15f, centerY - baseSize * 0.15f, baseSize * 0.35f, baseSize * 0.35f);
        break;
      case ANIM_CONFETTI:
        canvas.noStroke();
        canvas.fill(255, 110, 170, alpha * 255);
        canvas.rect(centerX - baseSize * 0.9f, centerY - baseSize * 0.2f, baseSize * 0.3f, baseSize * 1.0f);
        canvas.fill(120, 200, 255, alpha * 255);
        canvas.triangle(centerX - baseSize * 0.2f, centerY - baseSize * 0.5f,
                        centerX + baseSize * 0.5f, centerY - baseSize * 0.2f,
                        centerX - baseSize * 0.05f, centerY + baseSize * 0.1f);
        canvas.fill(255, 200, 90, alpha * 255);
        canvas.rect(centerX - baseSize * 0.3f, centerY + baseSize * 0.3f, baseSize * 0.8f, baseSize * 0.25f);
        canvas.fill(150, 255, 200, alpha * 255);
        canvas.triangle(centerX + baseSize * 0.4f, centerY + baseSize * 0.1f,
                        centerX + baseSize * 0.9f, centerY + baseSize * 0.5f,
                        centerX + baseSize * 0.25f, centerY + baseSize * 0.6f);
        break;
      case ANIM_CATER:
        canvas.stroke(40, 80, 35, alpha * 255);
        canvas.strokeWeight(max(1.0f, baseSize * 0.06f));
        for (int i = 0; i < 6; i++) {
          float segX = centerX - baseSize * 1.0f + i * baseSize * 0.4f;
          float segSize = baseSize * (0.6f - i * 0.05f);
          canvas.fill(130 - i * 6, 205 - i * 5, 120 - i * 4, alpha * 255);
          canvas.ellipse(segX, centerY + sin(i * 0.6f) * baseSize * 0.15f, segSize, segSize * 0.75f);
        }
        canvas.noStroke();
        float headX = centerX + baseSize * 0.5f;
        canvas.fill(255, 255, 255, alpha * 220);
        canvas.ellipse(headX - baseSize * 0.12f, centerY - baseSize * 0.18f, baseSize * 0.2f, baseSize * 0.22f);
        canvas.ellipse(headX + baseSize * 0.08f, centerY - baseSize * 0.16f, baseSize * 0.18f, baseSize * 0.2f);
        canvas.fill(0, alpha * 255);
        canvas.ellipse(headX - baseSize * 0.12f, centerY - baseSize * 0.2f, baseSize * 0.08f, baseSize * 0.1f);
        canvas.ellipse(headX + baseSize * 0.08f, centerY - baseSize * 0.19f, baseSize * 0.08f, baseSize * 0.1f);
        break;
    }

    canvas.popStyle();
  }
  
  // Cycle to next animation type
  void nextAnimationType() {
    currentAnimationType = (currentAnimationType + 1) % animationTypeNames.length;
  }
  
  // Snapshot current animation state (used for undo/save)
  String[] serializeState() {
    ArrayList<String> data = new ArrayList<String>();

    globalCloudDensity = animationParamValues[ANIM_CLOUD];
    data.add("ANIMATED_PEN_V1");
    data.add("globalCloudDensity:" + globalCloudDensity);
    data.add("animationCount:" + animations.size());
    StringBuilder paramLine = new StringBuilder("PARAMS:");
    for (int i = 0; i < animationParamValues.length; i++) {
      if (i > 0) paramLine.append(',');
      paramLine.append(animationParamValues[i]);
    }
    data.add(paramLine.toString());

    for (AnimationInstance anim : animations) {
      String animData = "ANIMATION:";

      if (anim instanceof CloudAnimation) {
        CloudAnimation cloud = (CloudAnimation)anim;
        animData += "CLOUD,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += cloud.cloudDensity;
      } else if (anim instanceof StarSparkleAnimation) {
        StarSparkleAnimation star = (StarSparkleAnimation)anim;
        animData += "STAR,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += star.sparkleDensity;
      } else if (anim instanceof RibbonFlutterAnimation) {
        RibbonFlutterAnimation ribbon = (RibbonFlutterAnimation)anim;
        animData += "RIBBON,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += ribbon.densityParam;
      } else if (anim instanceof FlowerBloomAnimation) {
        FlowerBloomAnimation flower = (FlowerBloomAnimation)anim;
        animData += "FLOWER,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += flower.rotationParam;
      } else if (anim instanceof CandyPopAnimation) {
        CandyPopAnimation candy = (CandyPopAnimation)anim;
        animData += "CANDY,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += candy.scatterParam;
      } else if (anim instanceof FireflyDriftAnimation) {
        FireflyDriftAnimation firefly = (FireflyDriftAnimation)anim;
        animData += "FIREFLY,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += firefly.densityParam;
      } else if (anim instanceof ConfettiBurstAnimation) {
        ConfettiBurstAnimation confetti = (ConfettiBurstAnimation)anim;
        animData += "CONFETTI,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += confetti.burstParam;
      } else if (anim instanceof CaterpillarAnimation) {
        CaterpillarAnimation bug = (CaterpillarAnimation)anim;
        animData += "CATER,";
        animData += anim.originX + ",";
        animData += anim.originY + ",";
        animData += anim.baseSize + ",";
        animData += bug.speedParam;
      }

      data.add(animData);
    }

    return data.toArray(new String[0]);
  }

  // Restore animation state from serialized data
  void deserializeState(String[] data) {
    animations.clear();
    animationParamValues = animationParamDefaults.clone();
    globalCloudDensity = animationParamValues[ANIM_CLOUD];

    if (data == null || data.length == 0) {
      return;
    }

    if (!data[0].equals("ANIMATED_PEN_V1")) {
      return;
    }

    for (int i = 1; i < data.length; i++) {
      String line = data[i];

      if (line.startsWith("globalCloudDensity:")) {
        globalCloudDensity = Float.parseFloat(line.split(":")[1]);
        if (animationParamValues != null && animationParamValues.length > ANIM_CLOUD) {
          animationParamValues[ANIM_CLOUD] = globalCloudDensity;
        }
      } else if (line.startsWith("PARAMS:")) {
        String paramString = line.substring(7);
        String[] paramParts = split(paramString, ',');
        for (int j = 0; j < paramParts.length && j < animationParamValues.length; j++) {
          try {
            animationParamValues[j] = constrain(Float.parseFloat(paramParts[j]), 0, 1.0f);
          } catch (Exception ignored) {
          }
        }
        globalCloudDensity = animationParamValues[ANIM_CLOUD];
      } else if (line.startsWith("ANIMATION:")) {
        String[] parts = line.substring(10).split(",");
        if (parts.length >= 1) {
          String type = parts[0];

          if (type.equals("CLOUD") && parts.length >= 5) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float density = Float.parseFloat(parts[4]);
            animations.add(new CloudAnimation(x, y, size, density));
          } else if (type.equals("STAR") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_STAR];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new StarSparkleAnimation(x, y, size, param));
          } else if (type.equals("RIBBON") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_RIBBON];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new RibbonFlutterAnimation(x, y, size, param));
          } else if (type.equals("FLOWER") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_FLOWER];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new FlowerBloomAnimation(x, y, size, param));
          } else if (type.equals("CANDY") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_CANDY];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new CandyPopAnimation(x, y, size, param));
          } else if (type.equals("FIREFLY") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_FIREFLY];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new FireflyDriftAnimation(x, y, size, param));
          } else if (type.equals("CONFETTI") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_CONFETTI];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new ConfettiBurstAnimation(x, y, size, param));
          } else if (type.equals("BUBBLE") && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_FIREFLY];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new FireflyDriftAnimation(x, y, size, param));
          } else if ((type.equals("CATER") || type.equals("CLOUD2") || type.equals("JELLY")) && parts.length >= 4) {
            float x = Float.parseFloat(parts[1]);
            float y = Float.parseFloat(parts[2]);
            float size = Float.parseFloat(parts[3]);
            float param = animationParamDefaults[ANIM_CATER];
            if (parts.length >= 5) {
              try {
                param = constrain(Float.parseFloat(parts[4]), 0, 1.0f);
              } catch (Exception ignored) {}
            }
            animations.add(new CaterpillarAnimation(x, y, size, param));
          }
        }
      }
    }
  }

  // Save animations to file
  void saveToFile(String filename) {
    saveStrings(filename, serializeState());
  }

  // Load animations from file
  void loadFromFile(String filename) {
    try {
      String[] data = loadStrings(filename);
      if (data == null) return;
      deserializeState(data);
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

// Sparkly star animation - rotating twinkles
class StarSparkleAnimation extends AnimationInstance {
  ArrayList<SparkleParticle> sparkles;
  float boundingRadius;
  float sparkleDensity;

  StarSparkleAnimation(float x, float y, float size, float densityParam) {
    super(x, y, size);
    sparkles = new ArrayList<SparkleParticle>();
    sparkleDensity = constrain(densityParam, 0, 1.0f);
    boundingRadius = max(size * 1.2, 18);
    int sparkleCount = constrain((int)(size * (0.18f + sparkleDensity * 0.7f)), 6, 36);
    for (int i = 0; i < sparkleCount; i++) {
      sparkles.add(new SparkleParticle(baseSize));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    for (SparkleParticle sparkle : sparkles) {
      sparkle.update(deltaSeconds, timeScale, baseSize);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (SparkleParticle sparkle : sparkles) {
      float wobble = sin(sparkle.twinklePhase) * sparkle.wobbleAmplitude;
      float px = originX + cos(sparkle.angle) * (sparkle.radius + wobble);
      float py = originY + sin(sparkle.angle * 1.05f) * (sparkle.radius * 0.7f + wobble) + sparkle.verticalOffset;
      float drawY = py - scrollY;

      if (drawY < -80 || drawY > canvas.height + 80) {
        continue;
      }

      float alpha = sparkle.getAlpha();
      float starSize = sparkle.size;

      canvas.stroke(red(sparkle.glowColor), green(sparkle.glowColor), blue(sparkle.glowColor), alpha * 160);
      canvas.strokeWeight(2.5);
      canvas.line(px - starSize, drawY, px + starSize, drawY);
      canvas.line(px, drawY - starSize, px, drawY + starSize);

      canvas.stroke(red(sparkle.mainColor), green(sparkle.mainColor), blue(sparkle.mainColor), alpha * 255);
      canvas.strokeWeight(1.2);
      float diag = starSize * 0.7;
      canvas.line(px - diag, drawY - diag, px + diag, drawY + diag);
      canvas.line(px - diag, drawY + diag, px + diag, drawY - diag);

      canvas.noStroke();
      canvas.fill(255, 255, 255, alpha * 200);
      canvas.ellipse(px, drawY, starSize * 0.6, starSize * 0.6);
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }
}

class SparkleParticle {
  float radius;
  float angle;
  float angularVelocity;
  float size;
  float twinklePhase;
  float twinkleSpeed;
  float wobbleAmplitude;
  float verticalOffset;
  float age;
  float maxAge;
  color mainColor;
  color glowColor;

  SparkleParticle(float baseSize) {
    reset(baseSize);
  }

  void reset(float baseSize) {
    radius = random(baseSize * 0.2, baseSize * 1.4);
    angle = random(TWO_PI);
    angularVelocity = random(-0.8, 0.8);
    size = random(baseSize * 0.15, baseSize * 0.4);
    twinklePhase = random(TWO_PI);
    twinkleSpeed = random(2.0, 4.0);
    wobbleAmplitude = random(baseSize * 0.05, baseSize * 0.2);
    verticalOffset = random(-baseSize * 0.3, baseSize * 0.3);
    age = random(0, 200);
    maxAge = random(1500, 2600);

    color[] palette = {
      color(255, 240, 150),
      color(255, 210, 240),
      color(190, 220, 255),
      color(255, 255, 220)
    };
    mainColor = palette[(int)random(palette.length)];
    glowColor = color(255, 255, 255);
  }

  void update(float deltaSeconds, float timeScale, float baseSize) {
    float scaledDelta = deltaSeconds;
    angle += angularVelocity * scaledDelta * 0.8;
    twinklePhase += twinkleSpeed * scaledDelta;
    age += deltaSeconds * 1000.0f;
    if (age > maxAge) {
      reset(baseSize);
    }
  }

  float getAlpha() {
    return constrain(0.4 + 0.6 * sin(twinklePhase), 0, 1);
  }
}

// Ribbon animation - fluttering strips of color
class RibbonFlutterAnimation extends AnimationInstance {
  ArrayList<RibbonPiece> ribbons;
  float boundingRadius;
  float densityParam;

  RibbonFlutterAnimation(float x, float y, float size, float param) {
    super(x, y, size);
    ribbons = new ArrayList<RibbonPiece>();
    densityParam = constrain(param, 0, 1.0f);
    boundingRadius = max(size * (1.0f + densityParam * 0.5f), 20);
    int count = constrain((int)(size * (0.12f + densityParam * 0.4f)), 4, 18);
    for (int i = 0; i < count; i++) {
      ribbons.add(new RibbonPiece(baseSize));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    for (RibbonPiece ribbon : ribbons) {
      ribbon.update(deltaSeconds, timeScale, baseSize);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (RibbonPiece ribbon : ribbons) {
      float px = originX + ribbon.offsetX;
      float py = originY + ribbon.offsetY - scrollY;

      if (py < -100 || py > canvas.height + 100) {
        continue;
      }

      float alpha = ribbon.getAlpha();

      canvas.pushMatrix();
      canvas.translate(px, py);
      canvas.rotate(ribbon.rotation + sin(ribbon.swayPhase) * 0.3f);
      canvas.scale(1.0, 1.0 + sin(ribbon.swayPhase * 1.3f) * 0.15f);

      float ribbonWidth = ribbon.length;
      float ribbonHeight = ribbon.thickness;

      canvas.noStroke();
      canvas.fill(red(ribbon.baseColor), green(ribbon.baseColor), blue(ribbon.baseColor), alpha * 180);
      canvas.beginShape();
      canvas.vertex(-ribbonWidth * 0.5f, -ribbonHeight * 0.5f);
      canvas.vertex(ribbonWidth * 0.5f, -ribbonHeight * 0.2f);
      canvas.vertex(ribbonWidth * 0.5f, ribbonHeight * 0.5f);
      canvas.vertex(-ribbonWidth * 0.5f, ribbonHeight * 0.2f);
      canvas.endShape(CLOSE);

      canvas.noFill();
      canvas.stroke(red(ribbon.trimColor), green(ribbon.trimColor), blue(ribbon.trimColor), alpha * 220);
      canvas.strokeWeight(1.4f);
      canvas.bezier(-ribbonWidth * 0.5f, -ribbonHeight * 0.3f,
                    -ribbonWidth * 0.2f, -ribbonHeight,
                    ribbonWidth * 0.2f, ribbonHeight,
                    ribbonWidth * 0.5f, ribbonHeight * 0.3f);

      canvas.popMatrix();
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }
}

class RibbonPiece {
  float offsetX;
  float offsetY;
  float swayPhase;
  float swaySpeed;
  float rotation;
  float rotationSpeed;
  float length;
  float thickness;
  float age;
  float maxAge;
  float verticalDrift;
  color baseColor;
  color trimColor;

  RibbonPiece(float baseSize) {
    reset(baseSize);
  }

  void reset(float baseSize) {
    float radius = random(baseSize * 0.03f, baseSize * 0.45f);
    float angle = random(TWO_PI);
    offsetX = cos(angle) * radius;
    offsetY = sin(angle) * radius;
    verticalDrift = random(-0.2, 0.2) * (baseSize / 20.0f);
    swayPhase = random(TWO_PI);
    swaySpeed = random(1.0, 2.6);
    rotation = random(-PI, PI);
    rotationSpeed = random(-0.4, 0.4);
    length = random(baseSize * 0.6, baseSize * 1.2);
    thickness = random(baseSize * 0.18, baseSize * 0.32);
    age = random(0, 300);
    maxAge = random(3200, 5200);

    color[] palette = {
      color(255, 180, 220),
      color(180, 220, 255),
      color(255, 210, 170),
      color(220, 255, 200)
    };
    baseColor = palette[(int)random(palette.length)];
    trimColor = lerpColor(baseColor, color(255), 0.25f);
  }

  void update(float deltaSeconds, float timeScale, float baseSize) {
    float scaledDelta = deltaSeconds;
    swayPhase += swaySpeed * scaledDelta;
    rotation += rotationSpeed * scaledDelta;
    offsetY += verticalDrift * timeScale + sin(swayPhase * 0.6f) * (baseSize * 0.005f);
    age += deltaSeconds * 1000.0f;
    if (age > maxAge) {
      reset(baseSize);
    }
  }

  float getAlpha() {
    float life = 1.0 - age / maxAge;
    life = constrain(life, 0, 1);
    return 0.4f + life * 0.6f;
  }
}

// Flower animation - blooming petals
class FlowerBloomAnimation extends AnimationInstance {
  ArrayList<FlowerBloom> blooms;
  float boundingRadius;
  float rotationParam;

  FlowerBloomAnimation(float x, float y, float size, float param) {
    super(x, y, size);
    blooms = new ArrayList<FlowerBloom>();
    rotationParam = constrain(param, 0, 1.0f);
    boundingRadius = max(size * (0.45f + rotationParam * 0.25f), 12);
    int count = constrain((int)(size * 0.15f), 4, 9);
    for (int i = 0; i < count; i++) {
      blooms.add(new FlowerBloom(baseSize, rotationParam));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    for (FlowerBloom bloom : blooms) {
      bloom.update(deltaSeconds, timeScale, baseSize);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (FlowerBloom bloom : blooms) {
      float px = originX + bloom.offsetX;
      float py = originY + bloom.offsetY - scrollY;

      if (py < -100 || py > canvas.height + 100) {
        continue;
      }

      float alpha = bloom.getAlpha();
      float scale = bloom.getScale(baseSize);

      canvas.pushMatrix();
      canvas.translate(px, py);
      canvas.rotate(bloom.rotation);

      int petals = bloom.petals;
      float petalWidth = scale * 0.45f;
      float petalHeight = scale * 0.9f;
      float petalStroke = max(0.6f, scale * 0.04f);

      for (int i = 0; i < petals; i++) {
        float angle = TWO_PI * i / petals;
        canvas.pushMatrix();
        canvas.rotate(angle);
        canvas.translate(0, scale * 0.6f);
        canvas.stroke(170, 170, 170, alpha * 220);
        canvas.strokeWeight(petalStroke);
        canvas.fill(red(bloom.petalColor), green(bloom.petalColor), blue(bloom.petalColor), alpha * 235);
        canvas.ellipse(0, 0, petalWidth, petalHeight);
        canvas.popMatrix();
      }

      canvas.fill(red(bloom.centerColor), green(bloom.centerColor), blue(bloom.centerColor), alpha * 255);
      canvas.noStroke();
      canvas.ellipse(0, 0, scale * 0.65f, scale * 0.65f);

      canvas.fill(255, 255, 255, alpha * 180);
      canvas.ellipse(scale * 0.12f, -scale * 0.1f, scale * 0.2f, scale * 0.2f);

      canvas.popMatrix();
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }
}

class FlowerBloom {
  float offsetX;
  float offsetY;
  float rotation;
  float age;
  float bloomDuration;
  float maxAge;
  int petals;
  color petalColor;
  color centerColor;
  float rotateParam;

  FlowerBloom(float baseSize, float densityParam) {
    this.rotateParam = constrain(densityParam, 0, 1.0f);
    reset(baseSize);
  }

  void reset(float baseSize) {
    float radius = random(baseSize * 0.03f, baseSize * 0.45f);
    float angle = random(TWO_PI);
    offsetX = cos(angle) * radius;
    offsetY = sin(angle) * radius;
    rotation = random(TWO_PI);
    petals = (int)random(6, 8);
    age = random(0, 200);
    bloomDuration = random(400, 900);
    maxAge = random(2600, 4200);

    petalColor = color(255, 255, 255);
    centerColor = color(255, 215, 90);
  }

  void update(float deltaSeconds, float timeScale, float baseSize) {
    age += deltaSeconds * 1000.0f;
    float spinSpeed = lerp(0.12f, 1.4f, rotateParam);
    rotation += spinSpeed * deltaSeconds;
    if (age > maxAge) {
      reset(baseSize);
    }
  }

  float getScale(float baseSize) {
    float t = constrain(age / bloomDuration, 0, 1);
    float ease = t * t * (3 - 2 * t); // smooth-step ease
    float baseFactor = 0.2f;
    float easeFactor = 0.3f;
    return baseSize * (baseFactor + ease * easeFactor);
  }

  float getAlpha() {
    float fade = 1.0f;
    if (age > maxAge * 0.75f) {
      float tail = (age - maxAge * 0.75f) / (maxAge * 0.25f);
      fade = 1.0f - constrain(tail, 0, 1);
    }
    return constrain(0.5f + fade * 0.5f, 0, 1);
  }
}

// Candy animation - colorful popping treats
class CandyPopAnimation extends AnimationInstance {
  ArrayList<CandyPiece> candies;
  float boundingRadius;
  float scatterParam;

  CandyPopAnimation(float x, float y, float size, float param) {
    super(x, y, size);
    candies = new ArrayList<CandyPiece>();
    scatterParam = constrain(param, 0, 1.0f);
    boundingRadius = max(size * (1.0f + scatterParam * 0.3f), 18);
    int count = constrain((int)(size * (0.15f + scatterParam * 0.45f)), 6, 26);
    for (int i = 0; i < count; i++) {
      candies.add(new CandyPiece(baseSize));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    for (CandyPiece candy : candies) {
      candy.update(deltaSeconds, timeScale, baseSize);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (CandyPiece candy : candies) {
      float px = originX + candy.getOffsetX();
      float py = originY + candy.getOffsetY() - scrollY;

      if (py < -120 || py > canvas.height + 120) {
        continue;
      }

      float alpha = candy.getAlpha();

      canvas.pushMatrix();
      canvas.translate(px, py);
      canvas.rotate(candy.rotation);
      float scale = candy.getScale();
      float size = baseSize * 0.4f * scale;

      canvas.noStroke();
      canvas.fill(red(candy.fillColor), green(candy.fillColor), blue(candy.fillColor), alpha * 255);

      switch(candy.shape) {
        case CandyPiece.SHAPE_CIRCLE:
          canvas.ellipse(0, 0, size, size);
          break;
        case CandyPiece.SHAPE_DIAMOND:
          canvas.beginShape();
          canvas.vertex(0, -size * 0.6f);
          canvas.vertex(size * 0.6f, 0);
          canvas.vertex(0, size * 0.6f);
          canvas.vertex(-size * 0.6f, 0);
          canvas.endShape(CLOSE);
          break;
        case CandyPiece.SHAPE_STAR:
          drawStar(canvas, size * 0.6f);
          break;
        case CandyPiece.SHAPE_HEART:
          drawHeart(canvas, size * 0.6f);
          break;
      }

      canvas.fill(255, 255, 255, alpha * 180);
      canvas.ellipse(size * 0.15f, -size * 0.15f, size * 0.25f, size * 0.25f);

      canvas.popMatrix();
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }

  void drawStar(PGraphics canvas, float size) {
    canvas.beginShape();
    int points = 5;
    for (int i = 0; i < points * 2; i++) {
      float angle = PI * i / points;
      float radius = (i % 2 == 0) ? size : size * 0.45f;
      canvas.vertex(cos(angle) * radius, sin(angle) * radius);
    }
    canvas.endShape(CLOSE);
  }

  void drawHeart(PGraphics canvas, float size) {
    canvas.beginShape();
    canvas.vertex(0, size * 0.6f);
    canvas.bezierVertex(size * 0.7f, size * 0.2f, size * 0.55f, -size * 0.5f, 0, -size * 0.2f);
    canvas.bezierVertex(-size * 0.55f, -size * 0.5f, -size * 0.7f, size * 0.2f, 0, size * 0.6f);
    canvas.endShape(CLOSE);
  }
}

class CandyPiece {
  static final int SHAPE_CIRCLE = 0;
  static final int SHAPE_DIAMOND = 1;
  static final int SHAPE_STAR = 2;
  static final int SHAPE_HEART = 3;

  int shape;
  float angle;
  float distance;
  float distanceSpeed;
  float wobblePhase;
  float wobbleSpeed;
  float verticalDrift;
  float rotation;
  float rotationSpeed;
  float scale;
  float targetScale;
  float age;
  float maxAge;
  color fillColor;

  CandyPiece(float baseSize) {
    reset(baseSize);
  }

  void reset(float baseSize) {
    shape = (int)random(4);
    angle = random(TWO_PI);
    distance = random(baseSize * 0.1, baseSize * 0.4);
    distanceSpeed = random(baseSize * 0.35f, baseSize * 0.6f) / 40.0f;
    wobblePhase = random(TWO_PI);
    wobbleSpeed = random(2.0, 4.0);
    verticalDrift = random(-0.3, 0.1) * (baseSize / 20.0f);
    rotation = random(-PI, PI);
    rotationSpeed = random(-1.2, 1.2);
    scale = random(0.4, 0.7);
    targetScale = random(0.9, 1.3);
    age = random(0, 200);
    maxAge = random(2000, 3600);

    color[] palette = {
      color(255, 110, 150),
      color(255, 190, 80),
      color(120, 200, 255),
      color(190, 255, 120),
      color(255, 150, 220)
    };
    fillColor = palette[(int)random(palette.length)];
  }

  void update(float deltaSeconds, float timeScale, float baseSize) {
    float scaledDelta = deltaSeconds;
    age += deltaSeconds * 1000.0f;
    wobblePhase += wobbleSpeed * scaledDelta;
    rotation += rotationSpeed * scaledDelta;

    distance += distanceSpeed * timeScale;
    if (distance > baseSize * 1.8f) {
      distance = baseSize * 0.2f;
    }

    scale = lerp(scale, targetScale, 0.03f * timeScale);
    if (age > maxAge) {
      reset(baseSize);
    }
  }

  float getOffsetX() {
    return cos(angle) * distance + cos(wobblePhase) * distance * 0.15f;
  }

  float getOffsetY() {
    return sin(angle) * distance + sin(wobblePhase * 1.2f) * distance * 0.12f + verticalDrift * age * 0.002f;
  }

  float getScale() {
    return scale;
  }

  float getAlpha() {
    float life = 1.0f - age / maxAge;
    life = constrain(life, 0, 1);
    return 0.6f + life * 0.4f;
  }
}

// Firefly animation - glowing particles with trailing light
class FireflyDriftAnimation extends AnimationInstance {
  ArrayList<FireflyParticle> fireflies;
  float boundingRadius;
  float densityParam;

  FireflyDriftAnimation(float x, float y, float size, float param) {
    super(x, y, size);
    fireflies = new ArrayList<FireflyParticle>();
    densityParam = constrain(param, 0, 1.0f);
    boundingRadius = max(size * 1.2f, 18);
    int count = constrain((int)(size * (0.18f + densityParam * 0.6f)), 6, 24);
    for (int i = 0; i < count; i++) {
      fireflies.add(new FireflyParticle(originX, originY, baseSize));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    for (FireflyParticle firefly : fireflies) {
      firefly.update(deltaSeconds, timeScale, originX, originY, baseSize);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (FireflyParticle firefly : fireflies) {
      float drawY = firefly.y - scrollY;
      if (drawY < -120 || drawY > canvas.height + 120) continue;

      // Draw trailing light
      canvas.stroke(255, 240, 160, firefly.getTrailAlpha() * 180);
      canvas.strokeWeight(1.4f);
      ArrayList<PVector> trail = firefly.trail;
      for (int i = 0; i < trail.size() - 1; i++) {
        PVector p1 = trail.get(i);
        PVector p2 = trail.get(i + 1);
        float alpha = map(i, 0, trail.size() - 1, 0, 160) * firefly.getTrailAlpha();
        canvas.stroke(255, 240, 160, alpha);
        canvas.line(p1.x, p1.y - scrollY, p2.x, p2.y - scrollY);
      }

      // Main glow
      float flicker = firefly.getFlicker();
      float glowSize = firefly.size * (0.6f + flicker * 0.8f);
      canvas.noStroke();
      canvas.fill(255, 240, 170, 90 * flicker);
      canvas.ellipse(firefly.x, drawY, glowSize * 2.0f, glowSize * 2.0f);
      canvas.fill(255, 255, 200, 140);
      canvas.ellipse(firefly.x, drawY, glowSize * 1.2f, glowSize * 1.2f);
      canvas.fill(255, 255, 255, 220);
      canvas.ellipse(firefly.x + glowSize * 0.18f, drawY - glowSize * 0.18f, glowSize * 0.35f, glowSize * 0.35f);
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }
}

class FireflyParticle {
  float x, y;
  float vx, vy;
  float size;
  float flickerPhase;
  float flickerSpeed;
  ArrayList<PVector> trail;

  FireflyParticle(float originX, float originY, float animSize) {
    size = max(2.5f, animSize * 0.25f);
    x = originX + random(-animSize * 0.6f, animSize * 0.6f);
    y = originY + random(-animSize * 0.6f, animSize * 0.6f);
    vx = random(-0.15f, 0.15f);
    vy = random(-0.1f, 0.1f);
    flickerPhase = random(TWO_PI);
    flickerSpeed = random(1.8f, 3.5f);
    trail = new ArrayList<PVector>();
  }

  void update(float deltaSeconds, float timeScale, float originX, float originY, float animSize) {
    float scaledDelta = deltaSeconds;

    // Gentle pull toward origin to keep them around the spawn point
    float spring = 0.0025f * (animSize / 20.0f);
    vx += (originX - x) * spring * scaledDelta;
    vy += (originY - y) * spring * scaledDelta;

    // Random wander
    vx += random(-0.04f, 0.04f) * scaledDelta;
    vy += random(-0.04f, 0.04f) * scaledDelta;

    // Damping
    vx *= pow(0.995f, timeScale);
    vy *= pow(0.995f, timeScale);

    // Move
    x += vx * timeScale * 4.0f;
    y += vy * timeScale * 4.0f;

    flickerPhase += flickerSpeed * scaledDelta;

    // Update trail
    trail.add(new PVector(x, y));
    int maxTrail = 10;
    while (trail.size() > maxTrail) {
      trail.remove(0);
    }
  }

  float getFlicker() {
    return constrain(0.45f + 0.55f * (sin(flickerPhase) * 0.6f + sin(flickerPhase * 1.9f + 1.3f) * 0.4f), 0.2f, 1.0f);
  }

  float getTrailAlpha() {
    return constrain(getFlicker(), 0, 1);
  }
}

// Confetti animation - celebratory bursts of paper bits
class ConfettiBurstAnimation extends AnimationInstance {
  ArrayList<ConfettiPiece> pieces;
  float boundingRadius;
  float burstParam;

  ConfettiBurstAnimation(float x, float y, float size, float param) {
    super(x, y, size);
    pieces = new ArrayList<ConfettiPiece>();
    burstParam = constrain(param, 0, 1.0f);
    boundingRadius = max(size * (1.2f + burstParam * 0.6f), 24);
    int count = constrain((int)(size * (0.25f + burstParam * 0.7f)), 10, 38);
    for (int i = 0; i < count; i++) {
      pieces.add(new ConfettiPiece(originX, originY, baseSize));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    for (ConfettiPiece piece : pieces) {
      piece.update(deltaSeconds, timeScale, originX, originY, baseSize);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (ConfettiPiece piece : pieces) {
      float drawY = piece.y - scrollY;
      if (drawY < -120 || drawY > canvas.height + 120) continue;

      canvas.pushMatrix();
      canvas.translate(piece.x, drawY);
      canvas.rotate(piece.rotation);

      canvas.fill(piece.baseColor, piece.getAlpha() * 255);
      canvas.noStroke();

      switch(piece.shape) {
        case ConfettiPiece.SHAPE_STRIP:
          canvas.rectMode(CENTER);
          canvas.rect(0, 0, piece.width, piece.height);
          canvas.rectMode(CORNER);
          break;
        case ConfettiPiece.SHAPE_TRIANGLE:
          canvas.beginShape();
          canvas.vertex(-piece.width * 0.5f, piece.height * 0.5f);
          canvas.vertex(piece.width * 0.5f, piece.height * 0.3f);
          canvas.vertex(0, -piece.height * 0.6f);
          canvas.endShape(CLOSE);
          break;
        case ConfettiPiece.SHAPE_WAVE:
          canvas.beginShape();
          canvas.vertex(-piece.width * 0.5f, -piece.height * 0.5f);
          canvas.vertex(0, -piece.height * 0.1f);
          canvas.vertex(piece.width * 0.5f, -piece.height * 0.5f);
          canvas.vertex(0, piece.height * 0.5f);
          canvas.endShape(CLOSE);
          break;
      }

      canvas.popMatrix();
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }
}

class ConfettiPiece {
  static final int SHAPE_STRIP = 0;
  static final int SHAPE_TRIANGLE = 1;
  static final int SHAPE_WAVE = 2;

  float x, y;
  float vx, vy;
  float rotation;
  float rotationSpeed;
  float width, height;
  float age;
  float maxAge;
  int shape;
  color baseColor;

  ConfettiPiece(float originX, float originY, float animSize) {
    reset(originX, originY, animSize);
  }

  void reset(float originX, float originY, float animSize) {
    float burst = max(10, animSize * 0.8f);
    x = originX + random(-burst * 0.2f, burst * 0.2f);
    y = originY + random(-burst * 0.2f, burst * 0.2f);
    float angle = random(TWO_PI);
    float speed = random(animSize * 0.12f, animSize * 0.35f);
    vx = cos(angle) * speed * 0.3f;
    vy = sin(angle) * speed * 0.3f - random(animSize * 0.05f);
    rotation = random(TWO_PI);
    rotationSpeed = random(-2.5f, 2.5f);
    width = random(animSize * 0.08f, animSize * 0.22f);
    height = random(animSize * 0.08f, animSize * 0.18f);
    age = 0;
    maxAge = random(1200, 2200);
    shape = (int)random(3);

    color[] palette = {
      color(255, 105, 180),
      color(255, 220, 120),
      color(120, 200, 255),
      color(150, 255, 180),
      color(255, 170, 220)
    };
    baseColor = palette[(int)random(palette.length)];
  }

  void update(float deltaSeconds, float timeScale, float originX, float originY, float animSize) {
    float scaledDelta = deltaSeconds;

    age += deltaSeconds * 1000.0f;
    rotation += rotationSpeed * scaledDelta;

    vy += animSize * 0.0025f * scaledDelta; // gentle gravity
    vx *= pow(0.995f, timeScale);
    vy *= pow(0.995f, timeScale);

    x += vx * timeScale * 3.0f;
    y += vy * timeScale * 3.0f;

    if (age > maxAge || y > originY + animSize * 2.0f) {
      reset(originX, originY, animSize);
    }
  }

  float getAlpha() {
    float life = 1.0f - age / maxAge;
    return constrain(0.2f + life * 0.8f, 0, 1);
  }
}

// Caterpillar animation - cute green crawler segments
class CaterpillarAnimation extends AnimationInstance {
  ArrayList<CaterpillarSegment> segments;
  float baseTime = 0;
  float pathRadius;
  float speed;
  float boundingRadius;
  float speedParam;

  CaterpillarAnimation(float x, float y, float size, float param) {
    super(x, y, size);
    segments = new ArrayList<CaterpillarSegment>();
    speedParam = constrain(param, 0, 1.0f);
    pathRadius = max(size * (0.35f + speedParam * 0.35f), 10);
    speed = lerp(0.45f, 2.0f, speedParam);
    boundingRadius = max(size * 1.0f, 18);

    int count = constrain((int)(size * (0.22f + speedParam * 0.25f)), 5, 14);
    for (int i = 0; i < count; i++) {
      segments.add(new CaterpillarSegment(i, count, baseSize));
    }
  }

  void update(float deltaSeconds, float timeScale) {
    float scaledDelta = deltaSeconds;
    baseTime += scaledDelta * speed;

    for (CaterpillarSegment seg : segments) {
      seg.update(baseTime, scaledDelta, originX, originY, pathRadius, baseSize, speed);
    }
  }

  void draw(PGraphics canvas, float scrollY, boolean isZoomed, float zoomScale, float zoomOffsetX, float zoomOffsetY) {
    canvas.pushStyle();

    if (isZoomed) {
      canvas.pushMatrix();
      canvas.translate(zoomOffsetX, zoomOffsetY);
      canvas.scale(zoomScale);
    }

    for (int i = segments.size() - 1; i >= 0; i--) {
      CaterpillarSegment seg = segments.get(i);
      float drawY = seg.y - scrollY;
      if (drawY < -120 || drawY > canvas.height + 120) continue;

      canvas.pushMatrix();
      canvas.translate(seg.x, drawY);
      canvas.rotate(seg.orientation);

      canvas.stroke(40, 80, 35, 220);
      canvas.strokeWeight(max(1.0f, seg.size * 0.12f));
      canvas.fill(seg.bodyColor);
      canvas.ellipse(0, 0, seg.size * 1.1f, seg.size * 0.8f);

      if (seg.isHead) {
        float eyeOffsetX = seg.size * 0.18f;
        float eyeOffsetY = -seg.size * 0.1f;
        canvas.noStroke();
        canvas.fill(0);
        canvas.ellipse(-eyeOffsetX, eyeOffsetY, seg.size * 0.1f, seg.size * 0.14f);
        canvas.ellipse(eyeOffsetX, eyeOffsetY, seg.size * 0.1f, seg.size * 0.14f);

        canvas.stroke(40, 80, 35, 200);
        canvas.strokeWeight(seg.size * 0.08f);
        canvas.line(-seg.size * 0.3f, -seg.size * 0.4f, -seg.size * 0.45f, -seg.size * 0.7f);
        canvas.line(seg.size * 0.3f, -seg.size * 0.4f, seg.size * 0.45f, -seg.size * 0.7f);

        canvas.noStroke();
        canvas.fill(255, 255, 255, 180);
        canvas.ellipse(-eyeOffsetX + seg.size * 0.02f, eyeOffsetY - seg.size * 0.03f, seg.size * 0.05f, seg.size * 0.06f);
        canvas.ellipse(eyeOffsetX + seg.size * 0.02f, eyeOffsetY - seg.size * 0.03f, seg.size * 0.05f, seg.size * 0.06f);
      } else {
        canvas.noStroke();
        canvas.fill(200, 255, 200, 160);
        canvas.ellipse(seg.size * 0.2f, -seg.size * 0.15f, seg.size * 0.25f, seg.size * 0.2f);
      }

      canvas.popMatrix();
    }

    if (isZoomed) {
      canvas.popMatrix();
    }

    canvas.popStyle();
  }

  boolean intersects(float x, float y, float radius) {
    float dist = dist(x, y, originX, originY);
    return dist < radius + boundingRadius;
  }

  boolean intersectsRect(float x, float y, float width, float height) {
    float halfW = width / 2;
    float halfH = height / 2;
    float nearestX = constrain(originX, x - halfW, x + halfW);
    float nearestY = constrain(originY, y - halfH, y + halfH);
    float dx = originX - nearestX;
    float dy = originY - nearestY;
    return dx * dx + dy * dy <= boundingRadius * boundingRadius;
  }
}

class CaterpillarSegment {
  float offset;
  float wobbleSeed;
  float orientation;
  float size;
  float x, y;
  boolean isHead;
  color bodyColor;
  float wigglePhase;
  float wiggleSpeed;

  CaterpillarSegment(int index, int total, float baseSize) {
    offset = index * 0.4f;
    wobbleSeed = random(TWO_PI);
    isHead = (index == 0);
    float sizeFactor = map(index, 0, total - 1, 1.0f, 0.6f);
    size = baseSize * 0.45f * sizeFactor;

    wigglePhase = random(TWO_PI);
    wiggleSpeed = random(4.0f, 7.0f);

    color headColor = color(120, 200, 110);
    color tailColor = color(90, 170, 95);
    bodyColor = lerpColor(headColor, tailColor, index / max(1.0f, total - 1.0f));
  }

  void update(float time, float delta, float originX, float originY, float radius, float baseSize, float baseSpeed) {
    float t = time - offset;
    float wobble = sin(t * 3.4f + wobbleSeed) * baseSize * 0.12f;
    float vertical = cos(t * 2.5f + wobbleSeed * 1.2f) * baseSize * 0.09f;

    wigglePhase += wiggleSpeed * delta * (1.2f * baseSpeed + 0.3f);
    float quickWiggle = sin(wigglePhase) * baseSize * (0.05f + baseSpeed * 0.05f);
    float quickLift = cos(wigglePhase * 1.7f + wobbleSeed) * baseSize * (0.05f + baseSpeed * 0.04f);

    x = originX + cos(t) * radius + wobble + quickWiggle;
    y = originY + sin(t) * radius * 0.5f + vertical + quickLift;

    float aheadX = cos(t + 0.2f) * radius;
    float aheadY = sin(t + 0.2f) * radius * 0.5f;
    float behindX = cos(t - 0.2f) * radius;
    float behindY = sin(t - 0.2f) * radius * 0.5f;
    orientation = atan2(aheadY - behindY, aheadX - behindX);
  }

  float getScale(float baseSize) {
    return size;
  }

  float getStretch() {
    return 1.0f;
  }
}
