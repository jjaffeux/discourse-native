int _generation = 0;

int get buildTreeMutationGeneration => _generation;

void notifyBuildTreeMutation() => _generation++;
