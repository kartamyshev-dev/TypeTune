#include <stddef.h>
#include <stdint.h>
typedef struct Bridge Bridge;
Bridge *typetune_bridge_new(void);
void typetune_bridge_free(Bridge *handle);
/* Exclusive ownership; input len must be <= 524288 bytes; output must have
   32768 bytes. No state-changing retry. */
size_t typetune_bridge_call(Bridge *handle, const uint8_t *input, size_t len, uint8_t *output);
