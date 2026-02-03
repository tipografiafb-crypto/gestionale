// Print & Cut Merger - Reset & Align Center
// 1. Clears existing content (to fix Page 1/2 confusion and keep Switch unhappy)
// 2. Places Page 1 (Graphics) -> Centers it
// 3. Places Page 2 (Cut) -> Centers it
// 4. Maintains valid document reference for Switch

#target illustrator

function main() {
    if (app.documents.length === 0) return "Error: No document open.";

    var doc = app.activeDocument;
    var filePath = doc.fullName.fsName; // Path to original PDF

    // 1. CLEAR DOCUMENT CONTENT
    // Delete all items to ensure clean slate
    app.executeMenuCommand('selectall');
    if (doc.selection.length > 0) {
        for (var i = doc.selection.length - 1; i >= 0; i--) {
            doc.selection[i].remove();
        }
    }
    // Delete extra layers (keep 1)
    while (doc.layers.length > 1) {
        doc.layers[0].remove();
    }

    // 2. PREPARE TEMP FILE (To allow placing same file)
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

    // 5. CLEANUP
    try { tempFile.remove(); } catch (e) { }

    return "Merged & Centered.";
}

function placeAndCenter(doc, layer, fileRef, pageNum) {
    // Set Prefs
    var pdfOptions = app.preferences.PDFFileOptions;
    var originalPage = pdfOptions.pageToOpen;
    var originalBox = pdfOptions.pDFCropToBox;

    pdfOptions.pageToOpen = pageNum;
    pdfOptions.pDFCropToBox = PDFBoxType.PDFMEDIABOX;

    // Place
    var item = layer.placedItems.add();
    item.file = fileRef;

    // Center Align
    // Calculate Artboard Center
    var abRect = doc.artboards[0].artboardRect; // [L, T, R, B]
    var abWidth = abRect[2] - abRect[0];
    var abHeight = abRect[1] - abRect[3]; // Top - Bottom (reversed in AI)
    var abCenter = [abRect[0] + abWidth / 2, abRect[1] - abHeight / 2];

    // Move Item Center to Artboard Center
    // Need to embed first to get accurate bounds?
    // No, place bounds are usually available.
    // NOTE: Illustrator coordinates Y is positive up, sometimes down? 
    // Usually: Rect = [Left, Top, Right, Bottom]. Top > Bottom.

    var itemBounds = item.geometricBounds;
    var itemWidth = itemBounds[2] - itemBounds[0];
    var itemHeight = itemBounds[1] - itemBounds[3];

    item.position = [
        abCenter[0] - itemWidth / 2,
        abCenter[1] + itemHeight / 2   // Set Top (Center Y + Half Height)
    ];

    // Restore Prefs
    pdfOptions.pageToOpen = originalPage;
    pdfOptions.pDFCropToBox = originalBox;

    // Embed
    item.embed();
}

main();
