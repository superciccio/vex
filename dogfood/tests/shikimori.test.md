---
api_url: https://shikimori.one/api/graphql
---

# Shikimori GraphQL API

## search anime by name
> **run** `shell`
```bash
curl -s '{{api_url}}' -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary '{"query":"{ animes(search: \"bakemono\", limit: 1, kind: \"!special\") { id malId name russian english japanese kind rating score status episodes episodesAired duration airedOn { year month day date } url season poster { id originalUrl mainUrl } genres { id name russian kind } studios { id name imageUrl } videos { id url name kind playerUrl imageUrl } screenshots { id originalUrl x166Url x332Url } scoresStats { score count } statusesStats { status count } description } }"}'
```
> **assert** `script`
```python
import json, os

assert int(os.environ["VEX_STATUS"]) == 0, "expected exit code 0"

data = json.loads(os.environ["VEX_STDOUT"])

assert isinstance(data, dict), "data should be object"
assert "data" in data, "missing field: data"
assert isinstance(data["data"], dict), "data.data should be object"
assert "animes" in data["data"], "missing field: animes"
assert isinstance(data["data"]["animes"], list), "data.data.animes should be array"
# length was: 1
if len(data["data"]["animes"]) > 0:
    assert isinstance(data["data"]["animes"][0], dict), "data.data.animes.0 should be object"
    assert "id" in data["data"]["animes"][0], "missing field: id"
    assert isinstance(data["data"]["animes"][0]["id"], str), "data.data.animes.0.id should be string"
    # value was: "6948"
    assert "malId" in data["data"]["animes"][0], "missing field: malId"
    assert isinstance(data["data"]["animes"][0]["malId"], str), "data.data.animes.0.malId should be string"
    # value was: "6948"
    assert "name" in data["data"]["animes"][0], "missing field: name"
    assert isinstance(data["data"]["animes"][0]["name"], str), "data.data.animes.0.name should be string"
    # value was: "Bakemonogatari Recap"
    assert "russian" in data["data"]["animes"][0], "missing field: russian"
    assert isinstance(data["data"]["animes"][0]["russian"], str), "data.data.animes.0.russian should be string"
    # value was: "Истории монстров: Рекап"
    assert "english" in data["data"]["animes"][0], "missing field: english"
    assert data["data"]["animes"][0]["english"] is None, "data.data.animes.0.english should be null"
    assert "japanese" in data["data"]["animes"][0], "missing field: japanese"
    assert isinstance(data["data"]["animes"][0]["japanese"], str), "data.data.animes.0.japanese should be string"
    # value was: "化物語"
    assert "kind" in data["data"]["animes"][0], "missing field: kind"
    assert isinstance(data["data"]["animes"][0]["kind"], str), "data.data.animes.0.kind should be string"
    # value was: "tv_special"
    assert "rating" in data["data"]["animes"][0], "missing field: rating"
    assert isinstance(data["data"]["animes"][0]["rating"], str), "data.data.animes.0.rating should be string"
    # value was: "r"
    assert "score" in data["data"]["animes"][0], "missing field: score"
    assert isinstance(data["data"]["animes"][0]["score"], (int, float)), "data.data.animes.0.score should be numeric"
    # value was: 7.29
    assert "status" in data["data"]["animes"][0], "missing field: status"
    assert isinstance(data["data"]["animes"][0]["status"], str), "data.data.animes.0.status should be string"
    # value was: "released"
    assert "episodes" in data["data"]["animes"][0], "missing field: episodes"
    assert isinstance(data["data"]["animes"][0]["episodes"], int), "data.data.animes.0.episodes should be integer"
    # value was: 1
    assert "episodesAired" in data["data"]["animes"][0], "missing field: episodesAired"
    assert isinstance(data["data"]["animes"][0]["episodesAired"], int), "data.data.animes.0.episodesAired should be integer"
    # value was: 0
    assert "duration" in data["data"]["animes"][0], "missing field: duration"
    assert isinstance(data["data"]["animes"][0]["duration"], int), "data.data.animes.0.duration should be integer"
    # value was: 24
    assert "airedOn" in data["data"]["animes"][0], "missing field: airedOn"
    assert isinstance(data["data"]["animes"][0]["airedOn"], dict), "data.data.animes.0.airedOn should be object"
    assert "year" in data["data"]["animes"][0]["airedOn"], "missing field: year"
    assert isinstance(data["data"]["animes"][0]["airedOn"]["year"], int), "data.data.animes.0.airedOn.year should be integer"
    # value was: 2009
    assert "month" in data["data"]["animes"][0]["airedOn"], "missing field: month"
    assert isinstance(data["data"]["animes"][0]["airedOn"]["month"], int), "data.data.animes.0.airedOn.month should be integer"
    # value was: 8
    assert "day" in data["data"]["animes"][0]["airedOn"], "missing field: day"
    assert isinstance(data["data"]["animes"][0]["airedOn"]["day"], int), "data.data.animes.0.airedOn.day should be integer"
    # value was: 7
    assert "date" in data["data"]["animes"][0]["airedOn"], "missing field: date"
    assert isinstance(data["data"]["animes"][0]["airedOn"]["date"], str), "data.data.animes.0.airedOn.date should be string"
    # value was: "2009-08-07"
    assert "url" in data["data"]["animes"][0], "missing field: url"
    assert isinstance(data["data"]["animes"][0]["url"], str), "data.data.animes.0.url should be string"
    assert data["data"]["animes"][0]["url"].startswith("http"), "data.data.animes.0.url should be a URL"
    # value was: https://shikimori.one/animes/6948-bakemonogatari-recap
    assert "season" in data["data"]["animes"][0], "missing field: season"
    assert data["data"]["animes"][0]["season"] is None, "data.data.animes.0.season should be null"
    assert "poster" in data["data"]["animes"][0], "missing field: poster"
    assert isinstance(data["data"]["animes"][0]["poster"], dict), "data.data.animes.0.poster should be object"
    assert "id" in data["data"]["animes"][0]["poster"], "missing field: id"
    assert isinstance(data["data"]["animes"][0]["poster"]["id"], str), "data.data.animes.0.poster.id should be string"
    # value was: "688299"
    assert "originalUrl" in data["data"]["animes"][0]["poster"], "missing field: originalUrl"
    assert isinstance(data["data"]["animes"][0]["poster"]["originalUrl"], str), "data.data.animes.0.poster.originalUrl should be string"
    assert data["data"]["animes"][0]["poster"]["originalUrl"].startswith("http"), "data.data.animes.0.poster.originalUrl should be a URL"
    # value was: https://shikimori.io/uploads/poster/animes/6948/c327a6799aee...
    assert "mainUrl" in data["data"]["animes"][0]["poster"], "missing field: mainUrl"
    assert isinstance(data["data"]["animes"][0]["poster"]["mainUrl"], str), "data.data.animes.0.poster.mainUrl should be string"
    assert data["data"]["animes"][0]["poster"]["mainUrl"].startswith("http"), "data.data.animes.0.poster.mainUrl should be a URL"
    # value was: https://shikimori.io/uploads/poster/animes/6948/main-cc8d85c...
    assert "genres" in data["data"]["animes"][0], "missing field: genres"
    assert isinstance(data["data"]["animes"][0]["genres"], list), "data.data.animes.0.genres should be array"
    # length was: 3
    if len(data["data"]["animes"][0]["genres"]) > 0:
        assert isinstance(data["data"]["animes"][0]["genres"][0], dict), "data.data.animes.0.genres.0 should be object"
        assert "id" in data["data"]["animes"][0]["genres"][0], "missing field: id"
        assert isinstance(data["data"]["animes"][0]["genres"][0]["id"], str), "data.data.animes.0.genres.0.id should be string"
        # value was: "7"
        assert "name" in data["data"]["animes"][0]["genres"][0], "missing field: name"
        assert isinstance(data["data"]["animes"][0]["genres"][0]["name"], str), "data.data.animes.0.genres.0.name should be string"
        # value was: "Mystery"
        assert "russian" in data["data"]["animes"][0]["genres"][0], "missing field: russian"
        assert isinstance(data["data"]["animes"][0]["genres"][0]["russian"], str), "data.data.animes.0.genres.0.russian should be string"
        # value was: "Тайна"
        assert "kind" in data["data"]["animes"][0]["genres"][0], "missing field: kind"
        assert isinstance(data["data"]["animes"][0]["genres"][0]["kind"], str), "data.data.animes.0.genres.0.kind should be string"
        # value was: "genre"
    assert "studios" in data["data"]["animes"][0], "missing field: studios"
    assert isinstance(data["data"]["animes"][0]["studios"], list), "data.data.animes.0.studios should be array"
    # length was: 1
    if len(data["data"]["animes"][0]["studios"]) > 0:
        assert isinstance(data["data"]["animes"][0]["studios"][0], dict), "data.data.animes.0.studios.0 should be object"
        assert "id" in data["data"]["animes"][0]["studios"][0], "missing field: id"
        assert isinstance(data["data"]["animes"][0]["studios"][0]["id"], str), "data.data.animes.0.studios.0.id should be string"
        # value was: "44"
        assert "name" in data["data"]["animes"][0]["studios"][0], "missing field: name"
        assert isinstance(data["data"]["animes"][0]["studios"][0]["name"], str), "data.data.animes.0.studios.0.name should be string"
        # value was: "Shaft"
        assert "imageUrl" in data["data"]["animes"][0]["studios"][0], "missing field: imageUrl"
        assert isinstance(data["data"]["animes"][0]["studios"][0]["imageUrl"], str), "data.data.animes.0.studios.0.imageUrl should be string"
        assert data["data"]["animes"][0]["studios"][0]["imageUrl"].startswith("http"), "data.data.animes.0.studios.0.imageUrl should be a URL"
        # value was: https://shikimori.io/system/studios/original/44.png?15032152...
    assert "videos" in data["data"]["animes"][0], "missing field: videos"
    assert isinstance(data["data"]["animes"][0]["videos"], list), "data.data.animes.0.videos should be array"
    # length was: 0
    assert "screenshots" in data["data"]["animes"][0], "missing field: screenshots"
    assert isinstance(data["data"]["animes"][0]["screenshots"], list), "data.data.animes.0.screenshots should be array"
    # length was: 30
    if len(data["data"]["animes"][0]["screenshots"]) > 0:
        assert isinstance(data["data"]["animes"][0]["screenshots"][0], dict), "data.data.animes.0.screenshots.0 should be object"
        assert "id" in data["data"]["animes"][0]["screenshots"][0], "missing field: id"
        assert isinstance(data["data"]["animes"][0]["screenshots"][0]["id"], str), "data.data.animes.0.screenshots.0.id should be string"
        # value was: "605468"
        assert "originalUrl" in data["data"]["animes"][0]["screenshots"][0], "missing field: originalUrl"
        assert isinstance(data["data"]["animes"][0]["screenshots"][0]["originalUrl"], str), "data.data.animes.0.screenshots.0.originalUrl should be string"
        assert data["data"]["animes"][0]["screenshots"][0]["originalUrl"].startswith("http"), "data.data.animes.0.screenshots.0.originalUrl should be a URL"
        # value was: https://shikimori.io/system/screenshots/original/677ff6fb6f2...
        assert "x166Url" in data["data"]["animes"][0]["screenshots"][0], "missing field: x166Url"
        assert isinstance(data["data"]["animes"][0]["screenshots"][0]["x166Url"], str), "data.data.animes.0.screenshots.0.x166Url should be string"
        assert data["data"]["animes"][0]["screenshots"][0]["x166Url"].startswith("http"), "data.data.animes.0.screenshots.0.x166Url should be a URL"
        # value was: https://shikimori.io/system/screenshots/x166/677ff6fb6f23fb1...
        assert "x332Url" in data["data"]["animes"][0]["screenshots"][0], "missing field: x332Url"
        assert isinstance(data["data"]["animes"][0]["screenshots"][0]["x332Url"], str), "data.data.animes.0.screenshots.0.x332Url should be string"
        assert data["data"]["animes"][0]["screenshots"][0]["x332Url"].startswith("http"), "data.data.animes.0.screenshots.0.x332Url should be a URL"
        # value was: https://shikimori.io/system/screenshots/x332/677ff6fb6f23fb1...
    assert "scoresStats" in data["data"]["animes"][0], "missing field: scoresStats"
    assert isinstance(data["data"]["animes"][0]["scoresStats"], list), "data.data.animes.0.scoresStats should be array"
    # length was: 10
    if len(data["data"]["animes"][0]["scoresStats"]) > 0:
        assert isinstance(data["data"]["animes"][0]["scoresStats"][0], dict), "data.data.animes.0.scoresStats.0 should be object"
        assert "score" in data["data"]["animes"][0]["scoresStats"][0], "missing field: score"
        assert isinstance(data["data"]["animes"][0]["scoresStats"][0]["score"], int), "data.data.animes.0.scoresStats.0.score should be integer"
        # value was: 10
        assert "count" in data["data"]["animes"][0]["scoresStats"][0], "missing field: count"
        assert isinstance(data["data"]["animes"][0]["scoresStats"][0]["count"], int), "data.data.animes.0.scoresStats.0.count should be integer"
        # value was: 848
    assert "statusesStats" in data["data"]["animes"][0], "missing field: statusesStats"
    assert isinstance(data["data"]["animes"][0]["statusesStats"], list), "data.data.animes.0.statusesStats should be array"
    # length was: 5
    if len(data["data"]["animes"][0]["statusesStats"]) > 0:
        assert isinstance(data["data"]["animes"][0]["statusesStats"][0], dict), "data.data.animes.0.statusesStats.0 should be object"
        assert "status" in data["data"]["animes"][0]["statusesStats"][0], "missing field: status"
        assert isinstance(data["data"]["animes"][0]["statusesStats"][0]["status"], str), "data.data.animes.0.statusesStats.0.status should be string"
        # value was: "planned"
        assert "count" in data["data"]["animes"][0]["statusesStats"][0], "missing field: count"
        assert isinstance(data["data"]["animes"][0]["statusesStats"][0]["count"], int), "data.data.animes.0.statusesStats.0.count should be integer"
        # value was: 4451
    assert "description" in data["data"]["animes"][0], "missing field: description"
    assert isinstance(data["data"]["animes"][0]["description"], str), "data.data.animes.0.description should be string"
    assert len(data["data"]["animes"][0]["description"]) > 0, "data.data.animes.0.description should not be empty"
```

