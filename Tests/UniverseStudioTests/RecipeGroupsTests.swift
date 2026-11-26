import Testing
@testable import UniverseStudio

struct RecipeGroupsTests {
    @Test func everyRecipeInExactlyOneGroup() {
        let listed = Recipe.groups.flatMap(\.recipes)
        #expect(listed.count == Recipe.allCases.count)
        #expect(Set(listed) == Set(Recipe.allCases))
    }
}
