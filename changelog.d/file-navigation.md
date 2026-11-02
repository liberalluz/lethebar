### Fixed

- Opening a download link on the site (for example `/lethebar/test-pack.zip`)
  showed the game instead of the file: the offline document fallback answered
  every top level navigation. Only a directory or `index.html` URL now gets the
  document.
