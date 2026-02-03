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

        // 3. Scale the Group
        // Resize around TOPLEFT to keep origin roughly consistent? 
        // actually CENTER might be safer if we refit artboard later.
        // Let's use TOPLEFT to minimize movement drift.
        tempGroup.resize(
            SCALE_FACTOR,
            SCALE_FACTOR,
            true, true, true, true,
            SCALE_FACTOR,
            Transformation.TOPLEFT
        );

        // 4. Ungroup (Optional - usually better to leave formatted files clean, but Group is fine)
        // Let's Ungroup to restore structure
        // tempGroup.remove() would delete items. We need to move them out? No, just leave properly.
        // Actually, for Cut files, a single group is often preferred. Let's KEEP the group.

        // 5. Force Stroke Weight (Post-Scaling)
        // Scaling also scales stroke weights (e.g. 1pt becomes 0.24pt). We must fix it.
        forceStrokeWeightRecursively(tempGroup, STROKE_WEIGHT, cutContourColor);

        // 6. Fit Artboard to Content
        doc.artboards[0].artboardRect = doc.visibleBounds;
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

main();
