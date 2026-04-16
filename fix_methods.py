import re

with open('TruchieEmu/Runner/CoreRunner.mm', 'r') as f:
    text = f.read()

# Fix setOptionValue missing context by putting it before @end
text = text.replace('\n- (void)setOptionValue:(NSString *)value forKey:(NSString *)key {}\n', '')
text = text.replace('@end\n\nint main', '- (void)setOptionValue:(NSString *)value forKey:(NSString *)key {}\n@end\n\nint main')

# Fix setupHWRender and setPixelFormat
text = text.replace('[g_runner setPixelFormat:(int)fmt];', '')
text = text.replace('[g_runner setupHWRender:cb];', '')

with open('TruchieEmu/Runner/CoreRunner.mm', 'w') as f:
    f.write(text)
