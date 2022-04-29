struct VGACharacter {
    char character;
    char color;
};

void kernel_main() {
    struct VGACharacter* buffer = ((struct VGACharacter *)0xb8000);
    struct VGACharacter emptyCharacter = { .color = 1, .character = ' ' };
    for(unsigned long i = 0; i < 25 * 50; i++) {
        *buffer = emptyCharacter;
        buffer++;
    }

}