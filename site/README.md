# site

The download page for agency, at agency.makors.xyz.

```sh
cd site
npm install
npm run dev      # work on it
npm run build    # output goes to dist/
```

The page reads the download link, size and checksum from `iso.makors.xyz/latest.json`, which the ISO build in makors/agency writes. `src/release.ts` has that address and the values to fall back on.

Visitor stats go to PostHog; `src/analytics.ts` lists the events, and it only runs on agency.makors.xyz. ISO downloads are counted on the server by `worker.js`, which answers `/download` and redirects to the file.

`/changelog` (`changelog.html`, `src/changelog.tsx`) lists the newest commits on main, read from the GitHub API when it loads.

Pushing to `main` deploys to agency.makors.xyz (Cloudflare Workers Builds).

The logos in `public/` are copies from `../docs`.
