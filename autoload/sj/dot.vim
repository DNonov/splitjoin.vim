let s:edge = '->'
" node regexp unused
let s:node = '\("*[^\"]\{-}"\|\i\+\)'

" Helper functions {{{
function! sj#dot#ExtractNodes(side)
  " Split multiple nodes into single elements
  " INPUT: 'A, B, C'
  " OUTPUT: ['A', 'B', 'C']
  " FIXME will fail on 'A, B, "some,label"'
  let nodes = split(a:side, ',')
  call sj#TrimList(nodes)
  call uniq(sort(nodes))
  return nodes
endfunction

function! s:TrimSemicolon(statement)
  return substitute(a:statement, ';$', '', '') 
endfunction

function! sj#dot#ExtractEdges(statement)
  " Extract elements of potentially chained edges as [src,dst] pairs
  " INPUT: 'A, B -> C -> D'
  " OUTPUT: [[[A, B], [C]], [[C], [D]]]
  let statement = s:TrimSemicolon(a:statement)
  " FIXME will fail if '->' inside "s
  let sides = split(statement, s:edge) 
  if len(sides) < 2 | return [] | endif
  let [edges, idx] = [[], 0]
  while idx < len(sides) - 1
    " handling of chained expressions
    " such as A -> B -> C
    let edges += [[sj#dot#ExtractNodes(get(sides, idx)),
          \ sj#dot#ExtractNodes(get(sides, idx + 1))]]
    let idx = idx + 1
  endwhile
  return edges
endfunction

function! s:ParseConsecutiveLines(...)
  " Could accept parameter for amount of lines to parse
  call sj#PushCursor()
  let s1 = s:TrimSemicolon(getline('.'))
  normal! j
  let s2 = s:TrimSemicolon(getline('.'))
  call sj#PopCursor()
  let edges1 = sj#dot#ExtractEdges(s1)
  let edges2 = sj#dot#ExtractEdges(s2)
  let edges = edges1 + edges2
  return edges
endfunction

function! s:Edge2string(edge)
  let edge = copy(a:edge)
  let edge = map(edge, 'join(v:val, ", ")')
  let edge = join(edge, ' -> ')
  let edge = edge . ';'
  return edge
endfunction

function! s:MergeEdges(edges)
  let edges = copy(a:edges)
  let finished = 0
  for [src_nodes, dst_nodes] in edges
    call uniq(sort(src_nodes))
    call uniq(sort(dst_nodes))
  endfor
  " all node sets sorted
  call uniq(sort(edges))
  " all edges sorted
  while !finished
    let finished = 1
    let idx = 0
    while idx < len(edges)
      let [source_nodes, dest_nodes] = edges[idx]
      let jdx = idx + 1
      while jdx < len(edges)
        if source_nodes == edges[jdx][0]
          let dest_nodes += edges[jdx][1]
          call uniq(sort(dest_nodes))
          let finished = 0
        elseif dest_nodes == edges[jdx][1]
          let source_nodes += edges[jdx][0]
          call uniq(sort(source_nodes))
          let finished = 0
        endif
        if !finished
          unlet edges[jdx]
        else
          let jdx += 1
        endif
      endwhile
      let idx = idx + 1
    endwhile
    call uniq(sort(edges))
  endwhile
  return edges
endfunction

function! s:ChainTransitiveEdges(edges)
  let edges = copy(a:edges)
  let finished = 0
  while !finished
    let finished = 1
    let idx = 0
    while idx < len(edges)
      let jdx = idx + 1
      while jdx < len(edges)
        if edges[idx][-1] == edges[jdx][0]
          " FIXME
          let edges[idx] += [edges[jdx][-1]]
          let finished = 0
        endif
        if !finished
          unlet edges[jdx]
        else
          let jdx += 1
        endif
      endwhile
      let idx += 1
    endwhile
  endwhile
  return edges
endfunction

" }}}
" Callback functions {{{
function! sj#dot#SplitStatement()
  let statements = split(getline('.'), ';')
  if len(statements) < 2 | return 0 | endif
  call map(statements, 'v:val . ";"')
  call sj#ReplaceMotion('V', join(statements, "\n"))
  return 1
endfunction

function! sj#dot#JoinStatement()
  " unused
  join
endfunction

function! sj#dot#SplitChainedEdge()
  let line = getline('.')
  if line !~ s:edge . '.*' . s:edge | return 0 | endif
  let statement = s:TrimSemicolon(line)
  let edges = sj#dot#ExtractEdges(statement)
  call map(edges, 's:Edge2string(v:val)')
  call sj#ReplaceMotion('V', join(edges, "\n"))
  return 1
endfunction

function! sj#dot#JoinChainedEdge()
  let edges = s:ParseConsecutiveLines()
  let edges = s:ChainTransitiveEdges(edges)
  if len(edges) > 1 | return 0 | endif
  let edge_string = s:Edge2string(edges[0])
  call sj#ReplaceMotion('Vj', edge_string) 
  return 1
endif
endfunction

function! sj#dot#SplitMultiEdge()
  " chop off potential trailing ';'
  let statement = substitute(getline('.'), ';$', '', '') 
  let edges = sj#dot#ExtractEdges(statement)
  if !len(edges) | return 0 | endif

  let new_edges = []
  for edge in edges
    let [lhs, rhs] = edge
    for source_node in lhs
      for dest_node in rhs
        let new_edges += [source_node . ' ' . s:edge . ' ' . dest_node . ';']
      endfor
    endfor
  endfor
  let body = join(new_edges, "\n")
  call sj#ReplaceMotion('V', body)
  return 1
endfunction

function! sj#dot#JoinMultiEdge()
  let edges = s:ParseConsecutiveLines()
  let edges = s:MergeEdges(edges)
  if len(edges) > 1 | return 0 | endif
  call sj#ReplaceMotion('Vj', s:Edge2string(edges[0]))
  return 1
endfunction
" }}}