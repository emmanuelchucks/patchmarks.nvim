local repo_root = vim.uv.cwd()

vim.opt.runtimepath:prepend(repo_root)

local specs = {
  "tests/specs/review_session_spec.lua",
  "tests/specs/annotations_spec.lua",
  "tests/specs/preview_export_spec.lua",
  "tests/specs/lifecycle_spec.lua",
  "tests/specs/config_spec.lua",
}

for _, path in ipairs(specs) do
  dofile(vim.fs.joinpath(repo_root, path))()
end
