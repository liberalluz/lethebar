### Fixed

- In a narrow window the save slots pushed `Save` and `Load` past the right
  edge, so a player could not save or load at all. Each row now wraps its text
  inside the width the window leaves for the two buttons, and the stored
  preview is clipped to 24 characters with an ellipsis instead of taking the
  first 40 characters of the scene.
