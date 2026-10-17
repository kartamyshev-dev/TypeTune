// Author-owned persistence probe; no decompilation or target execution.
// @category LayoutPilot.Research
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressIterator;
import ghidra.program.model.listing.Function;
import ghidra.framework.options.Options;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;

public class ghidra_checkpoint extends GhidraScript {
    private static final String SHA = "19d0057a9bfc38ba590babff82b28b5bf496c0833bbbd221f502722c6e2a26e9";
    private static final String MARKER = "layoutpilot-persistent-project-v1";

    @Override public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2 || !(args[0].equals("create") || args[0].equals("reopen"))) {
            throw new IllegalArgumentException("Expected create|reopen and private output path");
        }
        if (!SHA.equals(currentProgram.getExecutableSHA256())) {
            throw new IllegalStateException("Target identity differs");
        }
        Function function = currentProgram.getFunctionManager().getFunctionAt(toAddr("1002e0030"));
        if (function == null) throw new IllegalStateException("Expected analyzed function absent");
        MessageDigest hash = MessageDigest.getInstance("SHA-256");
        AddressIterator addresses = function.getBody().getAddresses(true);
        long count = 0;
        while (addresses.hasNext()) {
            Address address = addresses.next();
            hash.update(currentProgram.getMemory().getByte(address));
            count++;
        }
        String digest = HexFormat.of().formatHex(hash.digest());
        Options options = currentProgram.getOptions("LayoutPilot Persistence Probe");
        if (args[0].equals("create")) {
            options.setString("marker", MARKER);
            options.setString("function_sha256", digest);
        } else if (!MARKER.equals(options.getString("marker", "")) ||
                   !digest.equals(options.getString("function_sha256", ""))) {
            throw new IllegalStateException("Saved marker or function digest differs");
        }
        String report = "{\n" +
            "  \"phase\": \"" + args[0] + "\",\n" +
            "  \"target_sha256\": \"" + SHA + "\",\n" +
            "  \"program\": \"" + currentProgram.getName() + "\",\n" +
            "  \"language\": \"" + currentProgram.getLanguageID() + "\",\n" +
            "  \"function_entry\": \"0x1002e0030\",\n" +
            "  \"function_body_bytes\": " + count + ",\n" +
            "  \"function_body_sha256\": \"" + digest + "\",\n" +
            "  \"function_count\": " + currentProgram.getFunctionManager().getFunctionCount() + ",\n" +
            "  \"saved_marker\": \"" + options.getString("marker", "") + "\"\n" +
            "}\n";
        Files.writeString(Path.of(args[1]), report, StandardCharsets.UTF_8);
        println("LAYOUTPILOT_CHECKPOINT_OK " + args[0] + " " + digest);
    }
}
