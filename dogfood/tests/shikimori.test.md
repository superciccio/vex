---
api_url: https://shikimori.one/api/graphql
---

# Shikimori GraphQL API

## search anime by name
> **run** `shell`
```bash
curl -s '{{api_url}}' -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary '{"query":"{ animes(search: \"bakemono\", limit: 1, kind: \"!special\") { id malId name russian english japanese kind rating score status episodes episodesAired duration airedOn { year month day date } url season poster { id originalUrl mainUrl } genres { id name russian kind } studios { id name imageUrl } videos { id url name kind playerUrl imageUrl } screenshots { id originalUrl x166Url x332Url } scoresStats { score count } statusesStats { status count } description } }"}'
```
> **assert**
```ocaml
assert (status = 0);
assert (data.animes |> length > 0);
let first = data.animes.[0] in
assert (first |> matches_shape {
  id: string, malId: string, name: string,
  russian: string, japanese: string,
  kind: string, rating: string, status: string,
  score: number, episodes: int, episodesAired: int, duration: int,
  url: string, description: string,
  english: any?, season: any?,
  airedOn: { year: int, month: int, day: int, date: string },
  poster: { id: string, originalUrl: string, mainUrl: string },
  genres: [{ id: string, name: string, russian: string, kind: string }],
  studios: [{ id: string, name: string, imageUrl: string }],
  videos: [any],
  screenshots: [{ id: string, originalUrl: string, x166Url: string, x332Url: string }],
  scoresStats: [{ score: int, count: int }],
  statusesStats: [{ status: string, count: int }]
});
assert (first.url |> starts_with "https://");
assert (first.score > 0.0)
```
