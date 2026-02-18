// CutContour Converter and Scaler for Enfocus Switch
// Converts RGB(255,0,0) strokes to CutContour spot color
// Scales artwork from 72 DPI to 300 DPI (Factor: 24%)
// Forces 1pt stroke weight and fits artboard to content
// RECOMMENDED SWITCH SETTING: Open = "Open input file"

#target illustrator

function main() {
    var doc;

    if (app.documents.length > 0) {
        doc = app.activeDocument;
    } else {
        return "Error: No document open in Illustrator. Please set Open = 'Open input file' in Switch.";
    }

    // --- CONFIGURATION ---
    // Conversion from 72 DPI (Screen/SVG) to 300 DPI (Print)
    // Formula: 72 / 300 * 100 = 24%
    var SCALE_FACTOR = 24.0;
    var STROKE_WEIGHT = 1.0;

    var cutContourSpot = getOrCreateCutContourSpot(doc);
    var cutContourColor = new SpotColor();
    cutContourColor.spot = cutContourSpot;
    cutContourColor.tint = 100;

    // 1. Color Conversion (Pre-scaling)
    // We process paths first to ensure colors are correct before grouping
    var convertedCount = 0;
    convertedCount += processPathArray(doc.pathItems, cutContourColor);
    for (var j = 0; j < doc.compoundPathItems.length; j++) {
        convertedCount += processPathArray(doc.compoundPathItems[j].pathItems, cutContourColor);
    }
    for (var g = 0; g < doc.groupItems.length; g++) {
        convertedCount += processPathArray(doc.groupItems[g].pathItems, cutContourColor);
    }

    // 1b. Cleanup: Remove everything that is NOT CutContour
    // (e.g. 0pt bounding boxes, white backgrounds, etc.)
    cleanupNonCutItems(doc);

    // 2. Grouping for Scaling
    // IMPORTANT: We must group everything to scale it as a single unit, 
    // otherwise relative positions will be lost.
    app.executeMenuCommand('selectall');

    if (doc.selection.length > 0) {
        // Create a temporary group
        var tempGroup = doc.groupItems.add();

        // Move all selected items into the group
        // Note: Moving items changes the selection array, so we iterate backwards or use a copy
        // But simply moving selection is tricky. 
        // Safer way: Move all top-level items into the group.

        // Since we did 'selectall', we want to move the top-level selected objects.
        // Let's grab the selection array first.
        var itemsToMove = [];
        for (var i = 0; i < doc.selection.length; i++) {
            itemsToMove.push(doc.selection[i]);
        }

        // Move items into group
        for (var k = 0; k < itemsToMove.length; k++) {
            // Only move if it's not already in the group (sanity check)
            try {
                itemsToMove[k].move(tempGroup, ElementPlacement.PLACEATEND);
            } catch (e) {
                // Ignore errors (e.g. if item is locked or hidden)
            }
        }

        // 3. Proportional Scaling (Content + Artboard + Position)
        // We want to scale everything (artboard, position, size) by 24% to match PNG/Print density
        // without losing relative margins.

        var scaleDecimal = SCALE_FACTOR / 100.0;

        // A. Capture Original Properties
        var oldGroupPos = tempGroup.position; // [x, y]
        var oldArtboardRect = doc.artboards[0].artboardRect; // [L, T, R, B]

        // B. Scale the Group Content
        // Resize around TOPLEFT so the group's "position" anchor (Top-Left) remains the stable reference
        tempGroup.resize(
            SCALE_FACTOR,
            SCALE_FACTOR,
            true, true, true, true,
            SCALE_FACTOR,
            Transformation.TOPLEFT
        );

        // C. Reposition Group
        // Since we scaled around TopLeft, the group stayed at [oldX, oldY].
        // But in the new scaled universe, it should be at [oldX * s, oldY * s].
        tempGroup.position = [
            oldGroupPos[0] * scaleDecimal,
            oldGroupPos[1] * scaleDecimal
        ];

        // 4. Force Stroke Weight (Post-Scaling)
        forceStrokeWeightRecursively(tempGroup, STROKE_WEIGHT, cutContourColor);

        // 5. Scale Artboard
        // Apply the same scaling factor to the artboard coordinates
        var newRect = [
            oldArtboardRect[0] * scaleDecimal,
            oldArtboardRect[1] * scaleDecimal,
            oldArtboardRect[2] * scaleDecimal,
            oldArtboardRect[3] * scaleDecimal
        ];
        doc.artboards[0].artboardRect = newRect;
    }

    app.executeMenuCommand('deselectall');

    return "Done! Scaled to " + SCALE_FACTOR + "% (72->300 DPI). Converted paths.";
}

function processPathArray(pathItems, targetColor) {
    var count = 0;
    for (var i = 0; i < pathItems.length; i++) {
        var path = pathItems[i];
        if (isRedRGB(path.strokeColor) || (path.filled && isRedRGB(path.fillColor))) {
            path.stroked = true;
            path.strokeColor = targetColor;
            if (path.filled && isRedRGB(path.fillColor)) path.filled = false;
            count++;
        }
    }
    return count;
}

function forceStrokeWeightRecursively(item, weight, targetColor) {
    if (item.typename === "GroupItem") {
        for (var i = 0; i < item.pageItems.length; i++) {
            forceStrokeWeightRecursively(item.pageItems[i], weight, targetColor);
        }
    } else if (item.typename === "PathItem") {
        // Check if it's our cut contour
        if (item.strokeColor.typename == "SpotColor" && item.strokeColor.spot.name == "CutContour") {
            item.strokeWidth = weight;
        }
    } else if (item.typename === "CompoundPathItem") {
        // Compound paths share style on the parent usually, but let's check pathItems
        if (item.pathItems.length > 0) {
            var firstSub = item.pathItems[0];
            if (firstSub.strokeColor.typename == "SpotColor" && firstSub.strokeColor.spot.name == "CutContour") {
                // Changing pathItems[0] usually updates the whole compound path
                firstSub.strokeWidth = weight;
                // But loop to be safe if Illustrator allows mixed styles
                for (var p = 0; p < item.pathItems.length; p++) {
                    item.pathItems[p].strokeWidth = weight;
                }
            }
        }
    }
}

function getOrCreateCutContourSpot(doc) {
    var spotName = "CutContour";
    try { return doc.spots.getByName(spotName); } catch (e) {
        var newSpot = doc.spots.add();
        newSpot.name = spotName;
        var spotColor = new CMYKColor();
        spotColor.magenta = 100;
        newSpot.color = spotColor;
        newSpot.colorType = ColorModel.SPOT;
        return newSpot;
    }
}

function isRedRGB(color) {
    if (color.typename !== "RGBColor") return false;
    return (color.red > 250 && color.green < 10 && color.blue < 10);
}

function cleanupNonCutItems(doc) {
    var validItems = [];

    // Check Compound Paths first
    for (var i = 0; i < doc.compoundPathItems.length; i++) {
        var cp = doc.compoundPathItems[i];
        if (isCutContourItem(cp)) {
            validItems.push(cp);
        }
    }

    // Check PathItems
    for (var j = 0; j < doc.pathItems.length; j++) {
        var p = doc.pathItems[j];
        if (p.parent.typename === "CompoundPathItem") continue;

        if (isCutContourItem(p)) {
            validItems.push(p);
        }
    }

    var cleanLayer = doc.layers.add();
    cleanLayer.name = "CleanCut";

    for (var k = 0; k < validItems.length; k++) {
        try {
            validItems[k].move(cleanLayer, ElementPlacement.PLACEATEND);
        } catch (e) { }
    }

    for (var L = doc.layers.length - 1; L >= 0; L--) {
        if (doc.layers[L] !== cleanLayer) {
            doc.layers[L].remove();
        }
    }
}

function isCutContourItem(item) {
    try {
        // Direct check
        if (item.stroked && item.strokeColor.typename === "SpotColor" && item.strokeColor.spot.name === "CutContour") return true;

        // Compound Path check (often stroke is on the group, or on children)
        if (item.typename === "CompoundPathItem") {
            if (item.pathItems.length > 0) {
                var first = item.pathItems[0];
                if (first.stroked && first.strokeColor.typename === "SpotColor" && first.strokeColor.spot.name === "CutContour") return true;
            }
        }
    } catch (e) { }
    return false;


}

main();
