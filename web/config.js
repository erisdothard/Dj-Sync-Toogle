// Defaults baked into the page. Both are browser keys and visible to anyone who loads the page.
// The Spotify client ID is public by design (PKCE, no secret).
// The YouTube key must be restricted to HTTP referrers of the deployed sites in Google Cloud.
window.DJSYNC_DEFAULTS = {
  spotifyClientId: "ad94ecc1db3e49f7832ee36cd04e6a3f",
  youtubeApiKey: "AIzaSyBtsoSrw_PGogRYxY1TVsZfOx-5iJ3h8EE",
};
