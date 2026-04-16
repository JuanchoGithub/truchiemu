import re

with open('TruchieEmu/Engine/LibretroBridge.mm', 'r') as f:
    content = f.read()

# Extract from 'static int g_selectedLanguage' down to the end of 'bridge_environment'
start_marker = "static int g_selectedLanguage"
end_marker = "static void bridge_video_refresh"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("Could not find bounds")
    exit(1)

env_code = content[start_idx:end_idx]

# Now, we read CoreRunner.mm
with open('TruchieEmu/Runner/CoreRunner.mm', 'r') as f:
    runner_content = f.read()

# Replace the static bool env_callback in CoreRunner with the extracted bridge_environment
# Wait, we just inject the env_code before the CoreRunner implementation, and then use bridge_environment.

# We need to remove the dummy env_callback in CoreRunner.mm
runner_content = re.sub(r'static bool env_callback\([^)]+\) \{.*?(?=\nstatic void video_refresh_callback)', '', runner_content, flags=re.DOTALL)

# Inject the real env_code
injection_point = runner_content.find("static CoreRunner *g_runner = nil;")
if injection_point != -1:
    # Insert env_code right after g_runner
    new_runner_content = runner_content[:injection_point + len("static CoreRunner *g_runner = nil;")] + "\n\n" + env_code + "\n\n" + runner_content[injection_point + len("static CoreRunner *g_runner = nil;"):]
    
    # We must also change _retro_set_environment(env_callback) to _retro_set_environment(bridge_environment)
    new_runner_content = new_runner_content.replace("_retro_set_environment(env_callback);", "_retro_set_environment(bridge_environment);")
    
    # Write back
    with open('TruchieEmu/Runner/CoreRunner.mm', 'w') as out:
        out.write(new_runner_content)
    print("Successfully injected env code into CoreRunner.mm")
else:
    print("Could not find injection point")
