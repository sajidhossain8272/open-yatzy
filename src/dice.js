export class DiceComponent {
  constructor(index, x, y, size, onTap) {
    this.index = index;
    this.x = x;
    this.y = y;
    this.size = size;
    this.onTap = onTap;

    this.visualValue = 1;
    this.targetValue = 1;
    this.held = false;

    this.rollTimer = 0.0;
    this.rotationTorque = 0.0;
    this.angle = 0.0;
    this.scaleFactor = 1.0;

    this._rollTickTimer = 0.0;
    this._springVelocity = 0.0;
    this._springK = 220.0;
    this._springDamping = 14.0;
  }

  roll(resultValue) {
    this.targetValue = resultValue;
    this.rollTimer = 0.8 + Math.random() * 0.4;
    this.rotationTorque = (Math.random() > 0.5 ? 1 : -1) * (15 + Math.random() * 10);
    this.scaleFactor = 0.7;
    this._springVelocity = 0.0;
    this._rollTickTimer = 0.0;
  }

  triggerTapBounce() {
    this.scaleFactor = this.held ? 1.15 : 0.85;
    this._springVelocity = this.held ? 4.0 : -4.0;
  }

  update(dt) {
    if (this.rollTimer > 0) {
      this.rollTimer -= dt;
      this.angle += this.rotationTorque * dt;
      this.rotationTorque *= Math.exp(-1.5 * dt);

      this._rollTickTimer += dt;
      if (this._rollTickTimer > 0.06) {
        this._rollTickTimer = 0.0;
        this.visualValue = Math.floor(Math.random() * 6) + 1;
      }

      if (this.rollTimer <= 0) {
        this.visualValue = this.targetValue;
        this.angle = 0;
        this.scaleFactor = 1.25;
        this._springVelocity = 5.0;
      }
    } else {
      // Spring elastic bounce back to scale 1.0
      const displacement = this.scaleFactor - 1.0;
      const springForce = -this._springK * displacement - this._springDamping * this._springVelocity;
      this._springVelocity += springForce * dt;
      this.scaleFactor += this._springVelocity * dt;
    }
  }

  draw(ctx, unrolled = false) {
    ctx.save();
    
    // Move to center of die
    ctx.translate(this.x, this.y);
    // Apply rotation
    ctx.rotate(this.angle);
    // Apply scale
    ctx.scale(this.scaleFactor, this.scaleFactor);

    const hs = this.size / 2;

    // Fetch dynamic colors from the page styles
    const bodyStyle = getComputedStyle(document.body);
    const bgStart = unrolled ? '#202430' : (bodyStyle.getPropertyValue('--color-dice-bg-start').trim() || '#FFFFFF');
    const bgEnd = unrolled ? '#202430' : (bodyStyle.getPropertyValue('--color-dice-bg-end').trim() || '#F1F2F6');
    const dicePips = bodyStyle.getPropertyValue('--color-dice-pips').trim() || '#2C3E50';
    const diceBorder = unrolled ? 'rgba(255, 255, 255, 0.1)' : (bodyStyle.getPropertyValue('--color-dice-border').trim() || 'rgba(0, 0, 0, 0.1)');
    const goldAccent = bodyStyle.getPropertyValue('--color-accent-gold').trim() || '#FBBC05';

    // 1. Drop shadow (draw shifted round rect)
    ctx.save();
    ctx.shadowColor = 'rgba(2, 6, 23, 0.4)';
    ctx.shadowBlur = 8;
    ctx.shadowOffsetX = 3;
    ctx.shadowOffsetY = 6;
    ctx.fillStyle = 'rgba(0, 0, 0, 0.35)';
    ctx.beginPath();
    ctx.roundRect(-hs, -hs, this.size, this.size, 16);
    ctx.fill();
    ctx.restore();

    // 2. Glow outline when held
    if (this.held && !unrolled) {
      ctx.save();
      ctx.shadowColor = 'rgba(251, 188, 5, 0.6)';
      ctx.shadowBlur = 12;
      ctx.strokeStyle = goldAccent;
      ctx.lineWidth = 3.0;
      ctx.beginPath();
      ctx.roundRect(-hs, -hs, this.size, this.size, 16);
      ctx.stroke();
      ctx.restore();
    }

    // 3. Body (gradient matching the board game style)
    const grad = ctx.createLinearGradient(-hs, -hs, hs, hs);
    grad.addColorStop(0, bgStart);
    grad.addColorStop(1, bgEnd);
    
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.roundRect(-hs, -hs, this.size, this.size, 16);
    ctx.fill();

    // 4. Border stroke if not held or if unrolled
    if (!this.held || unrolled) {
      ctx.strokeStyle = diceBorder;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.roundRect(-hs, -hs, this.size, this.size, 16);
      ctx.stroke();
    }

    // 5. Draw Pips or Star
    if (unrolled) {
      this._drawStar(ctx, this.size);
    } else {
      this._drawPips(ctx, this.visualValue, this.size, dicePips);
    }

    ctx.restore();
  }

  _drawStar(ctx, size) {
    ctx.save();
    ctx.fillStyle = '#FFFFFF';
    ctx.beginPath();
    
    const spikes = 4;
    const outerRadius = size * 0.22;
    const innerRadius = size * 0.08;
    const cx = 0;
    const cy = 0;
    
    let rot = (Math.PI / 2) * 3;
    const step = Math.PI / spikes;

    ctx.moveTo(cx, cy - outerRadius);
    for (let i = 0; i < spikes; i++) {
      let x = cx + Math.cos(rot) * outerRadius;
      let y = cy + Math.sin(rot) * outerRadius;
      ctx.lineTo(x, y);
      rot += step;

      x = cx + Math.cos(rot) * innerRadius;
      y = cy + Math.sin(rot) * innerRadius;
      ctx.lineTo(x, y);
      rot += step;
    }
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  _drawPips(ctx, value, size, dicePips) {
    const radius = size * 0.085;
    const offset = size * 0.25;

    function drawPip(x, y) {
      // 3D depth shadow under pip
      ctx.fillStyle = 'rgba(0, 0, 0, 0.15)';
      ctx.beginPath();
      ctx.arc(x, y + 1.0, radius, 0, Math.PI * 2);
      ctx.fill();

      // Main pip
      ctx.fillStyle = dicePips;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();
    }

    switch (value) {
      case 1:
        drawPip(0, 0);
        break;
      case 2:
        drawPip(-offset, -offset);
        drawPip(offset, offset);
        break;
      case 3:
        drawPip(-offset, -offset);
        drawPip(0, 0);
        drawPip(offset, offset);
        break;
      case 4:
        drawPip(-offset, -offset);
        drawPip(offset, -offset);
        drawPip(-offset, offset);
        drawPip(offset, offset);
        break;
      case 5:
        drawPip(-offset, -offset);
        drawPip(offset, -offset);
        drawPip(0, 0);
        drawPip(-offset, offset);
        drawPip(offset, offset);
        break;
      case 6:
        drawPip(-offset, -offset);
        drawPip(offset, -offset);
        drawPip(-offset, 0);
        drawPip(offset, 0);
        drawPip(-offset, offset);
        drawPip(offset, offset);
        break;
    }
  }

  isTapped(mx, my) {
    return mx >= this.x - this.size / 2 &&
           mx <= this.x + this.size / 2 &&
           my >= this.y - this.size / 2 &&
           my <= this.y + this.size / 2;
  }
}
