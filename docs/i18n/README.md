# Myanmar translation review CSV

`seating-my-review.csv` lists the Myanmar strings added for reserved seating, for a native-speaker review.

Columns: `key,english,myanmar,where`.

- `key` is the string key in the code (ARB key, i18n key, or a label for API strings).
- `where` is the app it lives in: `user_app`, `crew_app`, `web`, `site` or `api`.
- Rows with key `TERM:...` and `where=all` are the shared glossary: the same term must be used in every app.

To send corrections back: edit the `myanmar` column (keep the header and the column order, quote fields that contain commas), leave `key` and `where` unchanged so each fix maps to its string, and return the file.
