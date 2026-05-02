/**
 * playwright-paginator — phone-crawl 의 SPA 페이지네이션 처리 사이드카.
 *
 * 사용처:
 *   - T-world / KT / LGU 공시지원금 페이지가 goPage(N) 같은 JS 로 페이지를 갱신.
 *   - self-hosted Firecrawl 의 playwright-service 는 actions(click/eval) 미지원.
 *   - 본 서비스가 N 페이지를 순회하며 각 페이지의 텍스트(또는 HTML) 를 수집해 합쳐 반환.
 *
 * 엔드포인트:
 *   POST /paginate { url, paginationJs, maxPages, waitMs?, viewportWidth? }
 *     - paginationJs: "goPage({n})" 같은 템플릿. {n} 자리에 1..maxPages 치환.
 *     - 응답: { success: true, pages: [{n, text}], aggregateText: "..." }
 *
 *   GET /healthz → 200
 *
 * 환경변수:
 *   PORT (default 3001)
 *   DEFAULT_TIMEOUT_MS (default 60000)
 */
const express = require('express');
const { chromium } = require('playwright');

const PORT = parseInt(process.env.PORT || '3001', 10);
const DEFAULT_TIMEOUT = parseInt(process.env.DEFAULT_TIMEOUT_MS || '60000', 10);

const app = express();
app.use(express.json({ limit: '2mb' }));

// 단일 브라우저 인스턴스 — 요청마다 컨텍스트만 새로 만들어 격리.
let browser;
async function getBrowser() {
    if (!browser) {
        browser = await chromium.launch({
            headless: true,
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
        });
    }
    return browser;
}

app.get('/healthz', (_req, res) => res.status(200).json({ ok: true }));

app.post('/paginate', async (req, res) => {
    const {
        url,
        paginationJs,
        maxPages = 1,
        waitMs = 4000,
        initialWaitMs = 4000,
        viewportWidth = 1280,
    } = req.body || {};

    if (!url || typeof url !== 'string') return res.status(400).json({ error: 'url required' });
    const pages = parseInt(maxPages, 10);
    if (!pages || pages < 1 || pages > 30) return res.status(400).json({ error: 'maxPages must be 1..30' });

    const startedAt = Date.now();
    let context;
    try {
        const b = await getBrowser();
        context = await b.newContext({
            viewport: { width: viewportWidth, height: 800 },
            userAgent: 'Mozilla/5.0 (Linux; Android 14; SM-S928N) AppleWebKit/537.36 KHTML, like Gecko Chrome/124.0.0.0 Mobile Safari/537.36',
        });
        const page = await context.newPage();
        page.setDefaultTimeout(DEFAULT_TIMEOUT);

        await page.goto(url, { waitUntil: 'domcontentloaded' });
        await page.waitForTimeout(initialWaitMs);

        const collected = [];

        for (let n = 1; n <= pages; n++) {
            if (n > 1 && paginationJs) {
                const expr = paginationJs.replace(/\{n\}/g, String(n));
                try {
                    await page.evaluate(expr);
                    await page.waitForTimeout(waitMs);
                } catch (e) {
                    collected.push({ n, error: `paginationJs failed: ${e.message?.substring(0, 200)}` });
                    continue;
                }
            }

            // body innerText — markdown 보다 LLM 친화적 (스크립트/스타일 제거된 보이는 텍스트)
            const text = await page.evaluate(() => document.body?.innerText || '');
            collected.push({ n, length: text.length, text: text.substring(0, 200_000) });
        }

        const aggregateText = collected
            .filter(p => p.text)
            .map(p => `\n--- PAGE ${p.n} ---\n${p.text}`)
            .join('\n');

        res.json({
            success: true,
            url,
            pages: collected.map(p => ({ n: p.n, length: p.length || 0, error: p.error })),
            aggregateText,
            durationMs: Date.now() - startedAt,
        });
    } catch (e) {
        console.error('[paginator] error', e);
        res.status(500).json({ success: false, error: e.message });
    } finally {
        if (context) await context.close().catch(() => {});
    }
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`[paginator] listening on ${PORT}`);
});

// graceful shutdown
process.on('SIGTERM', async () => {
    console.log('[paginator] SIGTERM — closing browser');
    if (browser) await browser.close().catch(() => {});
    process.exit(0);
});
