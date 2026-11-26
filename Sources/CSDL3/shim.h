#ifndef CSDL3_SHIM_H
#define CSDL3_SHIM_H

// The application owns `main`; Swift drives the SDL event loop directly.
#define SDL_MAIN_HANDLED 1

#include <SDL3/SDL.h>

#endif /* CSDL3_SHIM_H */
