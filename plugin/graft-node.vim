if exists('g:loaded_graft_node') || &cp | finish | endif

call RegisterGraftLoader("node", "javascript")
