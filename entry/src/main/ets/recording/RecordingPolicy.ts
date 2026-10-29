export interface CaptureSize {
  width: number;
  height: number;
  bitrate: number;
}

// Fit inside the selected long edge; never upscale or distort a desktop.
export function captureSize(width: number, height: number, longEdge: number, highQuality: boolean): CaptureSize {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width < 2 || height < 2) {
    throw new Error('无法获取有效的屏幕尺寸');
  }
  const scale = longEdge > 0 ? Math.min(1, longEdge / Math.max(width, height)) : 1;
  const outputWidth = Math.max(2, Math.floor(width * scale / 2) * 2);
  const outputHeight = Math.max(2, Math.floor(height * scale / 2) * 2);
  const pixels = outputWidth * outputHeight;
  // API 24 device rejects values above 30 Mbps during AVScreenCaptureRecorder.init.
  const bitrateLimit = highQuality ? 30000000 : 20000000;
  const bitrate = Math.round(Math.max(8000000, Math.min(bitrateLimit, pixels * (highQuality ? 9 : 6))));
  return { width: outputWidth, height: outputHeight, bitrate: bitrate };
}

export function isTerminalCaptureState(code: number): boolean {
  return code === 1 || code === 2 || code === 3 || code === 4 || code === 10;
}

export function captureStateMessage(code: number): string {
  if (code === 1) { return '已取消系统录屏授权'; }
  if (code === 2) { return '已从系统控制条停止'; }
  if (code === 3) { return '录屏被另一录屏会话中断'; }
  if (code === 4) { return '录屏被通话中断'; }
  if (code === 10) { return '用户切换，录屏已结束'; }
  if (code === 5) { return '麦克风暂不可用，画面继续录制'; }
  if (code === 6) { return '麦克风已被系统静音'; }
  if (code === 7) { return '麦克风已恢复'; }
  if (code === 8) { return '当前包含隐私内容，系统可能遮蔽画面'; }
  if (code === 9) { return '已离开隐私场景'; }
  return '';
}

export function durationText(milliseconds: number): string {
  const seconds = Math.max(0, Math.floor(milliseconds / 1000));
  const hours = Math.floor(seconds / 3600).toString().padStart(2, '0');
  const minutes = Math.floor(seconds % 3600 / 60).toString().padStart(2, '0');
  const remainder = (seconds % 60).toString().padStart(2, '0');
  return `${hours}:${minutes}:${remainder}`;
}
