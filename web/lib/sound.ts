'use client';

/**
 * Entry-confirmation sound for the website.
 *
 * A short bell-like chime plays after every successful save so the counter
 * never has to look at the screen to know the entry went in. The preference is
 * remembered in the browser and can be toggled from the top bar.
 */

let audio: HTMLAudioElement | null = null;
let enabled = true;

const STORAGE_KEY = 'nyota_sound_enabled';

export function isSoundEnabled(): boolean {
  return enabled;
}

export function initSound(): void {
  if (typeof window === 'undefined') return;
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    enabled = stored === null ? true : stored === 'true';
  } catch {
    enabled = true;
  }
}

export function setSoundEnabled(value: boolean): void {
  enabled = value;
  try {
    window.localStorage.setItem(STORAGE_KEY, value ? 'true' : 'false');
  } catch {
    /* private mode — keep the in-memory value */
  }
}

/** Plays the confirmation chime. Safe to call anywhere; never throws. */
export function playSuccess(): void {
  if (!enabled || typeof window === 'undefined') return;
  try {
    if (!audio) {
      audio = new Audio('/sounds/success.wav');
      audio.preload = 'auto';
    }
    audio.currentTime = 0;
    const p = audio.play();
    if (p && typeof p.catch === 'function') {
      p.catch(() => {
        /* autoplay blocked before a user gesture — ignore */
      });
    }
  } catch {
    /* ignore */
  }
}

/** Sound + vibration together — call after every successful save. */
export function confirmSave(): void {
  try {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
      navigator.vibrate(40);
    }
  } catch {
    /* ignore */
  }
  playSuccess();
}
