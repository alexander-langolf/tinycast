## ADDED Requirements

### Requirement: Closing the Monaco editor returns to Search Files

When Search Files opens a file in the Monaco editor, Tinycast SHALL show Search Files again after the editor closes.
The restored screen SHALL keep the query, the type filter and the selected result it had when the file opened.
The restored screen SHALL re-run the query through fsearch.
When the selected result no longer appears, the restored screen SHALL select the nearest remaining row.

#### Scenario: Close after editing a search result
- **WHEN** the user opens a result from Search Files in Monaco and then closes the editor
- **THEN** Search Files shows the same query and type filter with the same result selected

#### Scenario: The edited file disappears from the results
- **WHEN** the re-run query no longer returns the selected file
- **THEN** Search Files shows the new results with the nearest row selected

#### Scenario: Editor opened from elsewhere
- **WHEN** Monaco was opened without a File Navigator or Search Files origin
- **THEN** closing the editor shows no palette
