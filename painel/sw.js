/* Guarda o painel no celular para funcionar sem internet.
   Ao mudar qualquer arquivo do painel, aumente a VERSAO para o celular baixar a nova. */
const VERSAO = 'casa-franca-v1';
const ARQUIVOS = [
  './', 'index.html', 'manifest.webmanifest',
  'icones/icone-192.png', 'icones/icone-512.png', 'icones/icone-512-maskable.png', 'icones/apple-touch-icon.png',
  'bibliotecas/fontes/dm-sans.woff2', 'bibliotecas/fontes/fraunces.woff2',
  'bibliotecas/leitura-foto/tesseract.min.js', 'bibliotecas/leitura-foto/worker.min.js',
  'bibliotecas/leitura-foto/tesseract-core-lstm.wasm.js', 'bibliotecas/leitura-foto/tesseract-core-simd-lstm.wasm.js',
  'bibliotecas/leitura-foto/idioma/por.traineddata.gz',
  'bibliotecas/leitura-pdf/pdf.min.js', 'bibliotecas/leitura-pdf/pdf.worker.min.js',
  'bibliotecas/leitura-word/mammoth.browser.min.js',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSAO).then(c => c.addAll(ARQUIVOS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(chaves => Promise.all(chaves.filter(k => k !== VERSAO).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;

  // A página: tenta a internet primeiro (pega atualizações); sem internet, usa a guardada
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then(resp => { const copia = resp.clone(); caches.open(VERSAO).then(c => c.put('index.html', copia)); return resp; })
        .catch(() => caches.match('index.html'))
    );
    return;
  }

  // Bibliotecas, fontes e ícones: usa a cópia guardada (rápido e funciona offline)
  e.respondWith(
    caches.match(req, { ignoreSearch: true }).then(guardado => guardado || fetch(req))
  );
});
