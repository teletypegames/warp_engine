module WarpEngine
  VERSION = "0.5.1"

  # The header every API response carries. Named here rather than written out at the one
  # place that sets it: clients read it, the README documents it, and a string in three
  # places is a string that eventually differs in one of them.
  VERSION_HEADER = "WarpEngine-Version".freeze
end
