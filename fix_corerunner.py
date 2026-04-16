import re

with open('TruchieEmu/Runner/CoreRunner.mm', 'r') as f:
    text = f.read()

# Fix bridge_log_printf
text = text.replace('bridge_log_printf', 'runner_log_printf')

# Define runner_log_printf
log_def = """
#include <stdarg.h>
static void runner_log_printf(enum retro_log_level level, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    NSLog(@"[CoreRunner] %s", buf);
}
"""
text = text.replace('static int g_selectedLanguage = 0;', log_def + '\nstatic int g_selectedLanguage = 0;')

# Fix g_instance to g_runner
text = text.replace('g_instance', 'g_runner')

# Remove duplicate setOptionValue
text = re.sub(r'-\s*\(void\)setOptionValue:\(NSString\s*\*\)value\s*forKey:\(NSString\s*\*\)key\s*\{\}\n+', '', text)
text += "\n- (void)setOptionValue:(NSString *)value forKey:(NSString *)key {}\n" # Add back once at end

# Fix GLuint
text = text.replace('static GLuint g_hwFBO = 0;', 'static unsigned int g_hwFBO = 0;')

# Fix IOSurface cast
text = text.replace('frameReadyWithSurface:(id)_surface', 'frameReadyWithSurface:(__bridge IOSurface *)_surface')

with open('TruchieEmu/Runner/CoreRunner.mm', 'w') as f:
    f.write(text)
