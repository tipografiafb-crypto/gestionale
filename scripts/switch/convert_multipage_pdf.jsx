// Print & Cut Merger - Reset & Align Center & Cleanup & Crop
// 1. Clears existing content
// 2. Places Page 1 (Graphics) -> Centers it
// 3. Places Page 2 (Cut) -> Centers it
// 4. Cleans CutContour layer (removes unwanted boxes)
// 5. Fits Artboard to valid CutContour bounds

#target illustrator

function main() {
    if (app.documents.length === 0) return "Error: No document open.";

    var doc = app.activeDocument;
    var filePath = doc.fullName.fsName; // Path to original PDF

    // 1. CLEAR DOCUMENT CONTENT
    app.executeMenuCommand('selectall');
    if (doc.selection.length > 0) {
        for (var i = doc.selection.length - 1; i >= 0; i--) {
            doc.selection[i].remove();
        }
    }
    while (doc.layers.length > 1) {
        doc.layers[0].remove();
    }

    // 2. PREPARE TEMP FILE
    var tempPath = Folder.temp.fsName + "/temp_merge_" + new Date().getTime() + ".pdf";
    var tempFile = new File(tempPath);
    (new File(filePath)).copy(tempFile);

    // 3. IMPORT PAGE 1 (GRAPHICS)
    var layerGraphics = doc.layers[0];
    layerGraphics.name = "Graphics";

    placeAndCenter(doc, layerGraphics, tempFile, 1);
    layerGraphics.locked = true;

    // 4. IMPORT PAGE 2 (CUT)
    var layerCut = doc.layers.add();
    layerCut.name = "CutContour";

    placeAndCenter(doc, layerCut, tempFile, 2);

    // 5. CLEANUP CUT LAYER (Remove non-cut artifacts)
    cleanupCutLayer(layerCut);

    // 6. FIT ARTBOARD TO CUT CONTOUR
    app.executeMenuCommand('deselectall');

    // Select everything on CutContour layer
    layerCut.hasSelectedArtwork = true;

    if (doc.selection.length > 0) {
        var finalBounds = null;

        for (var k = 0; k < doc.selection.length; k++) {
            var item = doc.selection[k];
            var b = item.geometricBounds; // [L, T, R, B]

            if (finalBounds == null) {
                finalBounds = b;
            } else {
                finalBounds[0] = Math.min(finalBounds[0], b[0]);
                finalBounds[1] = Math.max(finalBounds[1], b[1]);
                finalBounds[2] = Math.max(finalBounds[2], b[2]);
                finalBounds[3] = Math.min(finalBounds[3], b[3]);
            }
        }

        if (finalBounds != null) {
            doc.artboards[0].artboardRect = finalBounds;
        }
    }
    app.executeMenuCommand('deselectall');

    // 7. CLEANUP TEMP
    try { tempFile.remove(); } catch (e) { }

    return "Merged, Cleaned & Cropped.";
}

function placeAndCenter(doc, layer, fileRef, pageNum) {
    var pdfOptions = app.preferences.PDFFileOptions;
    var originalPage = pdfOptions.pageToOpen;
    var originalBox = pdfOptions.pDFCropToBox;

    pdfOptions.pageToOpen = pageNum;
    pdfOptions.pDFCropToBox = PDFBoxType.PDFMEDIABOX;

    var item = layer.placedItems.add();
    item.file = fileRef;

    // Center Align
    var abRect = doc.artboards[0].artboardRect;
    var abWidth = abRect[2] - abRect[0];
    var abHeight = abRect[1] - abRect[3];
    var abCenter = [abRect[0] + abWidth / 2, abRect[1] - abHeight / 2];

    var itemBounds = item.geometricBounds;
    var itemWidth = itemBounds[2] - itemBounds[0];
    var itemHeight = itemBounds[1] - itemBounds[3];

    item.position = [
        abCenter[0] - itemWidth / 2,
        abCenter[1] + itemHeight / 2
    ];

    pdfOptions.pageToOpen = originalPage;
    pdfOptions.pDFCropToBox = originalBox;

    item.embed();
}

function cleanupCutLayer(layer) {
    // Iterate backwards to safely remove items
    for (var i = layer.pageItems.length - 1; i >= 0; i--) {
        var item = layer.pageItems[i];
        if (!keepItemRecursively(item)) {
            item.remove();
        }
    }
}

function keepItemRecursively(item) {
    try {
        if (item.typename === "GroupItem") {
            var hasValidChild = false;
            // Iterate backwards
            for (var j = item.pageItems.length - 1; j >= 0; j--) {
                if (keepItemRecursively(item.pageItems[j])) {
                    hasValidChild = true;
                } else {
                    item.pageItems[j].remove();
                }
            }
            return hasValidChild;
        }
        else if (item.typename === "PathItem") {
            return isCutContour(item);
        }
        else if (item.typename === "CompoundPathItem") {
            if (item.pathItems.length > 0) {
                return isCutContour(item.pathItems[0]);
            }
            return false;
        }
    } catch (e) { return false; }
    return false;
}

function isCutContour(path) {
    try {
        if (path.stroked && path.strokeColor.typename === "SpotColor" && path.strokeColor.spot.name === "CutContour") {
            return true;
        }
    } catch (e) { }
    return false;
}

main();
