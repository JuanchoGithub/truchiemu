#ifndef RcheevosCDReader_h
#define RcheevosCDReader_h

// Registers a custom CD reader that handles .cdi (DiscJuggler) files.
// Must be called before rcheevos_hash_generate().
void rcheevos_cdreader_register(void);

#endif /* RcheevosCDReader_h */
