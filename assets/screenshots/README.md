# Velvet Show — Landing Page

A static, dependency-free one-page site for velvetshow.app.

## Files

```
index.html       — page structure and content
styles.css       — all styling (design tokens at the top of the file)
script.js        — scroll-reveal + beta form mailto handler
assets/
  screenshots/
    hero-grid.jpg       — Velvet Lounge setlist grid (hero + "Songs & Shows")
    feature-lyrics.jpg  — lyrics/cue editor (used in "Stage Notes & Lyrics")
```

Everything else on the page (transport bar, waveform, MIDI cue list, transition
modal, stage display, panic button) is built directly in HTML/CSS to match the
app's interface — no extra image assets needed.

## Replacing or adding screenshots

If you want to swap in real app screenshots later:

- Keep images **dark** (#0B0D12 / #10131A range) so they sit naturally inside
  the `.window` chrome (the fake title bar with traffic-light dots).
- Recommended size: ~1600px wide, JPG at quality 80–85 is plenty for retina
  and keeps the page fast.
- Drop the file into `assets/screenshots/` and update the `src` in
  `index.html`. Each `<img>` already has descriptive `alt` text — update it to
  match the new image.

## Editing colors / type

All design tokens live at the top of `styles.css` under `:root`:

- `--bg`, `--bg-raised`, `--panel`, `--card` — surface layers
- `--blue` — Velvet selection/accent color
- `--gold` — MIDI / lighting cue accent
- `--red` — Panic only
- `--font-display` (Oswald), `--font-body` (Inter), `--font-mono` (JetBrains Mono)

## Beta download link (single source of truth)

All three "Download Beta" buttons (menu bar, hero, beta section) are driven
by **one constant** at the top of `script.js`:

```js
var VELVET_SHOW_DOWNLOAD_URL = 'https://github.com/Alxsparker/velvetshow/releases/download/v1.0.0/VELVET.SHOW.v1.0-2.zip';
```

The file is distributed via **GitHub Releases** on the `Alxsparker/velvetshow`
repo (tag `v1.0.0`), not Dropbox Transfer — Releases links are permanent and
do not expire, which was the original problem with the Dropbox link this
replaced.

**To ship a new build, edit only this one line in `script.js`.** Nothing in
`index.html` needs to change — each button is marked with a
`data-download-link` attribute and has its `href` set from this constant on
page load. The HTML `href="#beta"` you'll see on those buttons in the source
is just a safe fallback (scrolls to the beta section) in the rare case
JavaScript fails to load — it is not a second place you need to edit.

To publish a new version:
1. Go to `https://github.com/Alxsparker/velvetshow/releases/new`
2. Create a new tag (e.g. `v1.1.0`), upload the new `.zip` or `.dmg` as an
   asset, publish.
3. Copy the asset's download URL (format:
   `.../releases/download/{tag}/{filename}`) into `VELVET_SHOW_DOWNLOAD_URL`
   in `script.js`.

## Beta form

The "Join the Beta" form has no backend. On submit, `script.js` builds a
`mailto:` link to `alexandre.chalon@gmail.com` with the filled-in fields as
the email body. No data is stored or sent anywhere else.

To wire it to a real form backend later (e.g. Netlify Forms, Formspree):

1. Remove the `submit` handler in `script.js` (or just delete `script.js`'s
   form block).
2. Set the `<form>` tag's `action` to your form endpoint and `method="POST"`.
3. Add a `name` attribute convention your backend expects (the inputs already
   have `name="name"`, `name="email"`, `name="software"`, `name="mac"`).

## Deployment

This is a fully static site — three files plus an assets folder. Any static
host works:

**Netlify / Vercel**
- Drag-and-drop the `velvetshow` folder into the deploy UI, or connect a git
  repo with this folder as the root. No build command needed.

**GitHub Pages**
- Push this folder to a repo, enable Pages on the `main` branch (root), done.

**OVH / any shared hosting / FTP**
- Upload `index.html`, `styles.css`, `script.js`, and the `assets/` folder to
  your web root (e.g. `www/` or `public_html/`). No server-side requirements.

## Performance / accessibility notes

- Fonts are loaded from Google Fonts (Oswald, Inter, JetBrains Mono). For
  fully offline hosting, self-host the font files and update the `<link>`
  tags + `@font-face` accordingly.
- Respects `prefers-reduced-motion` (disables scroll-reveal animation and the
  waveform shimmer).
- All interactive elements are keyboard-focusable with a visible focus ring.
