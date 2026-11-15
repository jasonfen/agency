# site

The download page for agency, at agency.makors.xyz.

```sh
cd site
npm install
npm run dev      # work on it
npm run build    # output goes to dist/
```

The page reads the download link, size and checksum from `iso.makors.xyz/latest.json`, which the ISO build in makors/agency writes. `src/release.ts` has that address and the values to fall back on.

Pushing to `main` deploys to agency.makors.xyz (Cloudflare Workers Builds).

The logos in `public/` are copies from `../docs`.
