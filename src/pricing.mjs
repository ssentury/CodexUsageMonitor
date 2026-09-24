import fs from 'node:fs';
import { isPriced } from './catalog.mjs';

export function loadRateCard(rateCardPath) {
  return JSON.parse(fs.readFileSync(rateCardPath, 'utf8'));
}

export function priceUsage(model, usage, rateCard) {
  const rate = rateCard.models[model];
  if (!isPriced(rate)) {
    return { usd: null, credits: null };
  }

  const cacheWrite = Math.max(0, usage.cacheWriteTokens || 0);
  const input = Math.max(0, usage.inputTokens - usage.cachedInputTokens - cacheWrite);
  const cached = Math.max(0, usage.cachedInputTokens);
  const output = Math.max(0, usage.outputTokens);
  const isLongContext =
    rate.longContextThresholdTokens && usage.inputTokens > rate.longContextThresholdTokens;
  const inputMultiplier = isLongContext ? rate.longContextInputMultiplier || 1 : 1;
  const outputMultiplier = isLongContext ? rate.longContextOutputMultiplier || 1 : 1;
  const cacheWritePerMillion = rate.cacheWritePerMillion ?? rate.inputPerMillion;
  const creditsCacheWritePerMillion =
    rate.creditsCacheWritePerMillion ?? rate.creditsInputPerMillion;
  return {
    usd:
      (inputMultiplier *
          (input * rate.inputPerMillion +
            cached * rate.cachedInputPerMillion +
            cacheWrite * cacheWritePerMillion) +
        outputMultiplier * output * rate.outputPerMillion) /
      1_000_000,
    credits:
      (inputMultiplier *
          (input * rate.creditsInputPerMillion +
            cached * rate.creditsCachedInputPerMillion +
            cacheWrite * creditsCacheWritePerMillion) +
        outputMultiplier * output * rate.creditsOutputPerMillion) /
      1_000_000,
  };
}
