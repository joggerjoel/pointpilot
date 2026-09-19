import '@testing-library/jest-dom/vitest'

/**
 * jsdom does not implement matchMedia or requestAnimationFrame.
 *
 * Both are exercised by the count-up component, so they are stubbed here rather
 * than guarded for in production code — a guard would be dead weight on the two
 * browsers that matter.
 */

if (!window.matchMedia) {
  window.matchMedia = ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia
}

if (!window.requestAnimationFrame) {
  window.requestAnimationFrame = ((cb: FrameRequestCallback) =>
    setTimeout(() => cb(performance.now()), 16) as unknown as number) as typeof window.requestAnimationFrame
  window.cancelAnimationFrame = ((id: number) => clearTimeout(id)) as typeof window.cancelAnimationFrame
}
