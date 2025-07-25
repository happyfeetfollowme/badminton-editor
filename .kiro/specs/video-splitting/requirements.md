# Requirements Document

## Introduction

This feature implements video splitting functionality that allows users to divide videos into clips at specific time points. Users can select clips visually on the timeline, see them highlighted with white borders, and use a popup menu to split clips at the current playhead position. This enables precise video editing for badminton match analysis by creating logical segments.

## Requirements

### Requirement 1

**User Story:** As a badminton coach, I want to split videos into clips at specific time points, so that I can organize match footage into meaningful segments for analysis.

#### Acceptance Criteria

1. WHEN the video loads THEN the system SHALL treat the entire video as a single clip from start to end
2. WHEN a user taps on a clip in the thumbnail view THEN the system SHALL bound the clip with a white box and mark it as selected
3. WHEN a clip is already selected and the user taps on a different clip THEN the system SHALL remove the white box from the previously selected clip and bound the new clip with a white box
4. WHEN no clip is selected THEN the system SHALL display no white borders on any clips

### Requirement 2

**User Story:** As a user, I want to see which clip is currently selected, so that I can understand which segment I'm working with.

#### Acceptance Criteria

1. WHEN a clip is selected THEN the system SHALL display a white border around the entire clip area in the thumbnail view
2. WHEN a clip is selected THEN the system SHALL maintain the selection state until another clip is selected or the selection is cleared
3. WHEN the user taps on empty space in the timeline THEN the system SHALL clear any clip selection and remove all white borders

### Requirement 3

**User Story:** As a user, I want to access split functionality through an intuitive menu, so that I can easily split clips at the desired position.

#### Acceptance Criteria

1. WHEN a user taps on a selected clip THEN the system SHALL display a popup menu
2. WHEN the popup menu appears THEN the system SHALL position the menu with its center x-coordinate aligned to the center of the timeline view
3. WHEN the popup menu appears THEN the system SHALL position the menu's bottom edge above the thumbnail view with appropriate padding
4. WHEN the popup menu is displayed THEN the system SHALL show a split icon using the square-split-horizontal.svg asset

### Requirement 4

**User Story:** As a user, I want to split clips at the current playhead position, so that I can create precise segments based on the video content I'm viewing.

#### Acceptance Criteria

1. WHEN a user taps the split icon in the popup menu THEN the system SHALL create a split point at the current playhead time position
2. WHEN a split point is created THEN the system SHALL place a visual marker on the thumbnail at the playhead position
3. WHEN a split point is created THEN the system SHALL divide the selected clip into two separate clips at the split time
4. WHEN a clip is split THEN the system SHALL update the clip boundaries so that one clip ends at the split point and the next clip starts at the split point
5. WHEN a split is performed THEN the system SHALL maintain the visual markers for all split points on the timeline
6. WHEN a user taps the split icon THEN the system SHALL dismiss the popup menu and clear the clip selection

### Requirement 5

**User Story:** As a user, I want the system to manage clip boundaries automatically, so that clips are properly defined by split points and video boundaries.

#### Acceptance Criteria

1. WHEN the video is first loaded THEN the system SHALL define the first clip from the beginning of the video to either the first split point or the end of the video
2. WHEN split points exist THEN the system SHALL define each clip from one split point to the next split point
3. WHEN split points exist THEN the system SHALL define the last clip from the final split point to the end of the video
4. WHEN a new split point is added THEN the system SHALL recalculate all clip boundaries automatically
5. WHEN clips are defined THEN the system SHALL ensure no gaps or overlaps exist between adjacent clips