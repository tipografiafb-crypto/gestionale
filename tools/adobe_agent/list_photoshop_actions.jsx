#target photoshop
app.displayDialogs = DialogModes.NO;

var output = new File("/Users/switch/AutomationAdobe/photoshop-actions.txt");
output.encoding = "UTF8";
output.open("w");

var setIndex = 1;
while (true) {
  try {
    var setReference = new ActionReference();
    setReference.putIndex(charIDToTypeID("ASet"), setIndex);
    var setDescriptor = executeActionGet(setReference);
    var setName = setDescriptor.getString(charIDToTypeID("Nm  "));
    var actionCount = setDescriptor.getInteger(charIDToTypeID("NmbC"));

    for (var actionIndex = 1; actionIndex <= actionCount; actionIndex++) {
      var actionReference = new ActionReference();
      actionReference.putIndex(charIDToTypeID("Actn"), actionIndex);
      actionReference.putIndex(charIDToTypeID("ASet"), setIndex);
      var actionDescriptor = executeActionGet(actionReference);
      output.writeln(setName + "\t" + actionDescriptor.getString(charIDToTypeID("Nm  ")));
    }
    setIndex++;
  } catch (error) {
    break;
  }
}

output.close();
"actions-ok";
