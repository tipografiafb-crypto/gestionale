#target photoshop
app.displayDialogs = DialogModes.NO;
var inputFile = new File("/Users/switch/AutomationAdobe/test-input.png");
var outputFile = new File("/Users/switch/AutomationAdobe/test-photoshop.pdf");
var documentRef = app.open(inputFile);
var saveOptions = new PDFSaveOptions();
saveOptions.preserveEditing = false;
documentRef.saveAs(outputFile, saveOptions, true, Extension.LOWERCASE);
documentRef.close(SaveOptions.DONOTSAVECHANGES);
"photoshop-ok";
